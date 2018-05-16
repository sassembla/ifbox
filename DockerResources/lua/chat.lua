---- SETTINGS ----

-- upstream/downstream queue.
CHAT_REDIS_IP = "127.0.0.1"
CHAT_REDIS_PORT = 7777

-- CONNECTION_ID is nginx's request id. that len is 32. guidv4 length is 36, add four "0". 
-- overwritten by token.
CONNECTION_ID = ngx.var.request_id .. "0000"

-- max size of downstream message.
DOWNSTREAM_MAX_PAYLOAD_LEN = 1024


---- REQUEST HEADER PARAMS ----


local token = ngx.req.get_headers()["token"]
if not token then
	ngx.log(ngx.ERR, "no token.")

	-- remove below -- if must need token for chat.
	-- return

	token = "AAAAA"
	ngx.log(ngx.ERR, "token is:", token)
end

---- POINT BEFORE CONNECT ----

-- redis example.
if false then
	local redis = require "redis.redis"
	local redisConn = redis:new()
	local ok, err = redisConn:connect("127.0.0.1", 6379)

	if not ok then
		ngx.log(ngx.ERR, "connection:", CONNECTION_ID, " failed to generate redis client. err:", err)
		return
	end

	-- get value from redis using token.
	local res, err = redisConn:get(token)
	
	-- no key found => failed to authenticate.
	if not res then
		-- no key found.
		ngx.log(ngx.ERR, "connection:", CONNECTION_ID, " failed to authenticate. no token found in kvs.")

		-- 切断
		redisConn:close()
		ngx.exit(200)
		return
	elseif res == ngx.null then
		-- no value found.
		ngx.log(ngx.ERR, "connection:", CONNECTION_ID, " failed to authenticate. token is nil.")

		-- 切断
		redisConn:close()
		ngx.exit(200)
		return
	end

	-- delete got key.
	local ok, err = redisConn:del(token)

	-- 切断
	redisConn:close()

	-- 変数にセット、パラメータとして渡す。
	user_data = res
else
	user_data = token
	CONNECTION_ID = token
end

-- ngx.log(ngx.ERR, "connection:", CONNECTION_ID, " user_data:", user_data)















---- CONNECT ----

-- receive message from downstream via ws then send it to upstream.
function fromDownstreamToUpstream(user_data)
	-- start websocket serving.
	while true do
		local recv_data, typ, err = ws:recv_frame()

		if ws.fatal then
			ngx.log(ngx.ERR, "connection:", CONNECTION_ID, " closing accidentially. ", err)
			break
		end

		if not recv_data then
			ngx.log(ngx.ERR, "connection:", CONNECTION_ID, " received empty data.")
			-- log only. do nothing.
		end

		if typ == "close" then
			ngx.log(ngx.ERR, "connection:", CONNECTION_ID, " closing intentionally.")
			
			-- start close.
			break
		elseif typ == "ping" then
			local bytes, err = ws:send_pong(recv_data)
			-- ngx.log(ngx.ERR, "connection:", serverId, " ping received.")
			if not bytes then

				ngx.log(ngx.ERR, "connection:", serverId, " failed to send pong: ", err)
				break
			end

		elseif typ == "pong" then
			ngx.log(ngx.INFO, "client ponged")

		end
	end

	ws:send_close()
	ngx.log(ngx.ERR, "connection:", CONNECTION_ID, " connection closed")


	receiveJobConn:close()

	ngx.exit(200)
end

-- pull message from upstream and send it to downstream via udp/ws.
function fromUpstreamToDownstream()
	local localWs = ws
	local ok, err = receiveJobConn:subscribe(user_data)
	if not ok then
		ngx.log(ngx.ERR, "failed to generate subscriver")
		return
	end

	while true do
		-- receive message from disque queue, through CONNECTION_ID. 
		-- game context will send message via CONNECTION_ID.
		local res, err = receiveJobConn:read_reply()

		if not res then
			ngx.log(ngx.ERR, "redis subscribe read error:", err)
		else
		
			-- ngx.log(ngx.ERR, "receiving data:", #res)

			if not res then
				ngx.log(ngx.ERR, "err:", err)
				break
			else
				local sendingData = res[3]
				-- ngx.log(ngx.ERR, "client datas:", datas)
				
				-- split data with continuation frame if need.
				if (DOWNSTREAM_MAX_PAYLOAD_LEN < #sendingData) then
					local count = math.floor(#sendingData / DOWNSTREAM_MAX_PAYLOAD_LEN)
					local rest = #sendingData % DOWNSTREAM_MAX_PAYLOAD_LEN

					local index = 1
					local failed = false
					for i = 1, count do
						-- send. from index to index + DOWNSTREAM_MAX_PAYLOAD_LEN.
						local continueData = string.sub(sendingData, index, index + DOWNSTREAM_MAX_PAYLOAD_LEN - 1)

						local bytes, err = localWs:send_continue(continueData)
						if not bytes then
							failed = true
							break
						end
						index = index + DOWNSTREAM_MAX_PAYLOAD_LEN
					end

					if failed then
						break
					end

					-- send rest data as binary.
					
					local lastData = string.sub(sendingData, index)

					local bytes, err = localWs:send_binary(lastData)
					if not bytes then
						break
					end

				else
					-- send data to client via websocket.
					local bytes, err = localWs:send_binary(sendingData)
					
					if not bytes then
						break
					end
					--ngx.log(ngx.ERR, "receiving data5:", #res)
				end
			end
		end
	end

	ws:send_close()
	ngx.log(ngx.ERR, "connection:", CONNECTION_ID, " connection closed")

	receiveJobConn:close()
	
	ngx.exit(200)
end


do
	
	-- create upstream/downstream connection of disque.
	do
		local redis = require "redis.redis"

		-- downstream.
		receiveJobConn = redis:new()
		local ok, err = receiveJobConn:connect(CHAT_REDIS_IP, CHAT_REDIS_PORT)
		if not ok then
			ngx.log(ngx.ERR, "connection:", CONNECTION_ID, " failed to generate receiveJob client")
			return
		end
		receiveJobConn:set_timeout(1000 * 60 * 60)
	end


	-- setup websocket client
	do
		local wsServer = require "ws.websocketServer"

		ws, wErr = wsServer:new{
			timeout = 10000000,--10000sec. never timeout from server.
			max_payload_len = DOWNSTREAM_MAX_PAYLOAD_LEN
		}

		if not ws then
			ngx.log(ngx.ERR, "connection:", CONNECTION_ID, " failed to new websocket:", wErr)
			return
		end
	end


	-- start receiving message from upstream & sending message to downstream.
	ngx.thread.spawn(fromUpstreamToDownstream)


	-- start receiving message from downstream & sending message to upstream.
	fromDownstreamToUpstream(user_data)
end