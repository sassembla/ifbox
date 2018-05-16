docker rm -f ifbox

docker build -f ifbox.dockerfile -t ifbox .

docker run -td --name ifbox -p 8080:8080 -p 7777:7777 -v $(pwd)/logs:/nginx-1.13.6/1.13.6/logs ifbox