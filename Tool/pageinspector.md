```sh
PG_INCLUDE=$(/Users/zhougangjie/app/pgdebug/bin/pg_config --includedir-server)
make PG_CONFIG=/Users/zhougangjie/app/pgdebug/bin/pg_config CPPFLAGS="-I$PG_INCLUDE"
make install PG_CONFIG=/Users/zhougangjie/app/pgdebug/bin/pg_config
```