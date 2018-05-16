FROM centos

ENV NGINX_VERSION 1.13.6
ENV LUAJIT_VERSION 2.1.0-beta3
ENV NGINX_DEVEL_KIT_VERSION v0.3.0
ENV NGINX_LUAJIT_VERSION v0.10.11

# RUN rpm --import https://packages.microsoft.com/keys/microsoft.asc

# RUN sh -c 'echo -e "[packages-microsoft-com-prod]\nname=packages-microsoft-com-prod \nbaseurl=https://packages.microsoft.com/yumrepos/microsoft-rhel7.3-prod\nenabled=1\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" > /etc/yum.repos.d/dotnetdev.repo'

# ready tools.
RUN yum -y install \
  gcc \
  gcc-c++ \
  make \
  zlib-devel \
  pcre-devel \
  openssl-devel \
  wget \
  unzip \
  golang \
  libunwind \
  libicu


# download and make redis.
RUN wget http://download.redis.io/redis-stable.tar.gz && tar xzvf redis-stable.tar.gz && cd redis-stable && make && make install


# download nginx.
RUN wget http://nginx.org/download/nginx-$NGINX_VERSION.tar.gz && tar -xzvf nginx-$NGINX_VERSION.tar.gz && rm nginx-$NGINX_VERSION.tar.gz

# add luajit module.
RUN wget http://luajit.org/download/LuaJIT-$LUAJIT_VERSION.tar.gz && tar -xzvf LuaJIT-$LUAJIT_VERSION.tar.gz && rm LuaJIT-$LUAJIT_VERSION.tar.gz && cd LuaJIT-$LUAJIT_VERSION/ && make && make install

# add nginx tools, lua module and njs module.
RUN mkdir nginx-$NGINX_VERSION/dependencies && cd nginx-$NGINX_VERSION/dependencies && \
  wget https://github.com/simpl/ngx_devel_kit/archive/$NGINX_DEVEL_KIT_VERSION.zip && unzip $NGINX_DEVEL_KIT_VERSION.zip && rm $NGINX_DEVEL_KIT_VERSION.zip && \
  wget https://github.com/openresty/lua-nginx-module/archive/$NGINX_LUAJIT_VERSION.zip && unzip $NGINX_LUAJIT_VERSION.zip && rm $NGINX_LUAJIT_VERSION.zip


# add nginx build shell.
COPY ./DockerResources/build.sh nginx-$NGINX_VERSION/build.sh

# build nginx.
RUN cd nginx-$NGINX_VERSION && sh build.sh


# add lua sources.
RUN mkdir nginx-$NGINX_VERSION/$NGINX_VERSION/lua
COPY ./DockerResources/lua nginx-$NGINX_VERSION/$NGINX_VERSION/lua


# overwrite nginx conf.
COPY ./DockerResources/nginx.conf nginx-$NGINX_VERSION/$NGINX_VERSION/conf/



# run nginx & redis-server
ENTRYPOINT /nginx-$NGINX_VERSION/$NGINX_VERSION/sbin/nginx && cd /redis-stable/src && ./redis-server --port 7777 --protected-mode no


