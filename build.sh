#!/bin/bash

docker-compose down -v
rm -rf ./master/data/*
rm -rf ./slave/data/*
sleep 1

docker-compose build
docker-compose up -d
sleep 1

until docker exec mysql_master sh -c 'export MYSQL_PWD=111; mysql -u root -e ";"'
do
    echo "Waiting for mysql_master database connection..."
    sleep 4
done

PRIVILEGES_STMT='CREATE USER "mydb_slave_user"@"%" IDENTIFIED BY "mydb_slave_pwd"; GRANT REPLICATION SLAVE ON *.* TO "mydb_slave_user"@"%"; FLUSH PRIVILEGES;'
docker exec mysql_master sh -c "export MYSQL_PWD=111; mysql -u root -e '$PRIVILEGES_STMT'"

until docker-compose exec mysql_slave sh -c 'export MYSQL_PWD=111; mysql -u root -e ";"'
do
    echo "Waiting for mysql_slave database connection..."
    sleep 4
done

MS_STATUS=`docker exec mysql_master sh -c 'export MYSQL_PWD=111; mysql -u root -e "SHOW MASTER STATUS;"'`
CURRENT_LOG=`echo $MS_STATUS | awk '{print $6}'`
CURRENT_POS=`echo $MS_STATUS | awk '{print $7}'`

echo "Master's current log file = $CURRENT_LOG"
echo "Master's current log pos = $CURRENT_POS"

START_SLAVE_STMT="CHANGE MASTER TO MASTER_HOST='mysql_master',MASTER_USER='mydb_slave_user',MASTER_PASSWORD='mydb_slave_pwd',MASTER_LOG_FILE='$CURRENT_LOG',MASTER_LOG_POS=$CURRENT_POS; START SLAVE;"
START_SLAVE_CMD='export MYSQL_PWD=111; mysql -u root -e "'
START_SLAVE_CMD+="$START_SLAVE_STMT"
START_SLAVE_CMD+='"'

docker exec mysql_slave sh -c "$START_SLAVE_CMD"
docker exec mysql_slave sh -c "export MYSQL_PWD=111; mysql -u root -e 'SHOW SLAVE STATUS \G;'"

CREATE_READ_USER_STMT='CREATE USER "read_user"@"%" IDENTIFIED BY "read_pwd"; GRANT SELECT ON *.* TO "read_user"@"%";'
docker exec mysql_slave sh -c "export MYSQL_PWD=111; mysql -u root -e '$CREATE_READ_USER_STMT'"