#!/bin/bash

#
# Usage:
# screen -dmS autouam &&
# screen -x -S autouam -p 0 -X stuff "bash /root/autouam.sh" &&
# screen -x -S autouam -p 0 -X stuff $'\n'
#

# mode="load"
# 两种模式可选，一：cpu 二：load

challenge="1"
# 是否同时开启验证码质询 设为1即开启

keeptime="60"
# ≈开盾最小时间，如60 则开盾60秒内负载降低不会关，60秒后关

interval="0.5"
# 检测间隔时间，默认0.5秒

log="1"
# 是否开启日志，0=关，1=开

output="1"
# 是否开启状态输出，0=关，1=开

email="눈_눈"
# CloudFlare 账号邮箱

api_key="눈_눈"
# CloudFlare API KEY 使用Global API即可

zone_id="눈_눈"
# 区域ID 在域名的概述页面获取

default_security_level="high"
# 默认安全等级 关闭UAM时将会把安全等级调整为它

api_url="https://api.cloudflare.com/client/v4/zones/$zone_id/settings/security_level"
# API的地址

api_url1="https://api.cloudflare.com/client/v4/zones/$zone_id/firewall/rules"
# API的地址之二

api_url2="https://api.cloudflare.com/client/v4/zones/$zone_id/filters"
# API的地址之三

# 安装jq依赖，只会在脚本第一次运行时运行
if [[ ! $(which jq 2> /dev/null) ]] && [[ ! -f "status.txt" ]]; then
    echo "jq not found!"
    if [ -f "/usr/bin/apt-get" ]; then
        apt-get install -y jq
    elif [ -f "/usr/bin/dnf" ]; then
        dnf install -y epel-release
        dnf install -y jq
    elif [ -f "/usr/bin/yum" ]; then
        yum install -y epel-release
        yum install -y jq
    fi
fi

# 创建配置文件
if [ ! -f "status.txt" ]; then
echo "" > status.txt
fi
if [ ! -f "ruleid.txt" ]; then
echo "" > ruleid.txt
fi
if [ ! -f "filterid.txt" ]; then
echo "" > filterid.txt
fi
if [[ ! -f "log.txt" ]] && [[ "$log" -eq 1 ]]; then
echo "[`date`] 日志文件创建成功" > log.txt
fi
if [[ "$log" -eq 1 ]]; then
  echo "[`date`] 脚本已启动" >> log.txt
fi
for((;;))
do
  # 获取当前系统负载
  load=$(cat /proc/loadavg | colrm 5)
  # 获取CPU线程？核心数
  check=$(cat /proc/cpuinfo | grep "processor" | wc -l)
  # 获取当前运行状态
  status=$(cat status.txt)
  # 获取RuleID
  ruleid=$(cat ruleid.txt)
  # 获取FilterID
  filterid=$(cat filterid.txt)
  # 读取系统秒数，大概是这样子的：123812312
  now=$(date +%s)
  time=$(date +%s -r status.txt)
  newtime=`expr $now - $time`
  closetime=`expr $keeptime - $newtime`


  if [[ "$output" -eq 1 ]]; then
    # echo "当前模式:$mode"
    echo "系统负载:$load"
    if [[ "$status" -eq 1 ]]; then
      echo "防御已开启"
      if  [[ "$challenge" -eq 1 ]]; then
        echo "验证码已开启"
      fi
    else
      echo "防御已关闭"
    fi
  fi

  if [[ "$status" -eq 1 ]]; then

    if [[ $load <$check ]]&&[[ $newtime -gt $keeptime ]]; then
      if [[ "$log" -eq 1 ]]; then
        echo "[`date`] 负载低于$check，当前已开盾超过规定时间$newtime秒，调整至默认安全等级（$default_security_level）..." >> log.txt
      fi
      # 关闭UAM
      if [[ "$log" -eq 1 ]]; then
        echo "[`date`] UAM关闭中..." >> log.txt
      fi
      result=$(curl -X PATCH "$api_url" \
        -H "X-Auth-Email: $email" \
        -H "X-Auth-Key: $api_key" \
        -H "Content-Type: application/json" \
        --data "{
            \"value\": \"$default_security_level\"
        }" --silent \
      | jq -r '.success')
      if [ "$result" = "true" ]; then
        echo "0" > status.txt
        echo "[`date`] UAM关闭成功" >> log.txt
      else
        if [[ "$log" -eq 1 ]]; then
          echo "[`date`] 错误代码011 UAM关闭失败" >> log.txt
        fi
      fi
      if [[ "$challenge" -eq 1 ]]; then
        # 关闭验证码
        if [[ "$log" -eq 1 ]]; then
          echo "[`date`] 验证码关闭中..." >> log.txt
        fi
        result=$(curl -X DELETE "$api_url1/$ruleid" \
          -H "X-Auth-Email: $email" \
          -H "X-Auth-Key: $api_key" \
          -H "Content-Type: application/json" \
        --silent)
        result1=$(curl -X DELETE "$api_url2/$filterid" \
          -H "X-Auth-Email: $email" \
          -H "X-Auth-Key: $api_key" \
          -H "Content-Type: application/json" \
        --silent)

        if [ $(echo $result | jq -r '.success') -a $(echo $result1 | jq -r '.success') ]; then
          if [[ "$log" -eq 1 ]]; then
            echo "[`date`] 验证码关闭成功" >> log.txt
          fi
        else
          if [[ "$log" -eq 1 ]]; then
            echo "[`date`] 错误代码012 验证码关闭失败" >> log.txt
          fi
        fi
      fi
    elif [[ $load >$check ]] && [[ $newtime -gt $keeptime ]]; then
      if [[ "$log" -eq 1 ]]; then
        echo "[`date`] $mode负载高于$check，当前已开启UAM超过$keeptime秒，UAM无效" >> log.txt
      fi
    elif [[ $load>$check ]]; then
      if [[ "$log" -eq 1 ]]; then
        echo "[`date`] $mode负载高于$check，当前已开启($newtime秒)" >> log.txt
      fi
    else
      if [[ "$log" -eq 1 ]]; then
        echo "[`date`] $mode负载低于$check，不做任何改变，状态持续了$newtime秒" >> log.txt
        echo "[`date`] 将于$closetime秒后调整安全等级至$default_security_level" >> log.txt
      fi
    fi
  else
    if  [[ $load >$check ]]; then
      if [[ "$log" -eq 1 ]]; then
        echo "[`date`] $mode负载高于$check，UAM开启中..." >> log.txt
      fi
      # Enable Under Attack Mode
      result=$(curl -X PATCH "$api_url" \
        -H "X-Auth-Email: $email" \
        -H "X-Auth-Key: $api_key" \
        -H "Content-Type: application/json" \
        --data "{
          \"value\": \"under_attack\"
        }" --silent \
      | jq -r '.success')

      if [ "$result" = "true" ]; then
        echo "1" > status.txt
        if [[ "$log" -eq 1 ]]; then
         echo "[`date`] UAM开启成功" >> log.txt
        fi
      else
        if [[ "$log" -eq 1 ]]; then
          echo "[`date`] 错误代码001 UAM开启失败" >> log.txt
        fi
      fi

      if [ "$challenge" -eq 1 ]; then
        if [[ "$log" -eq 1 ]]; then
          echo "[`date`] 验证码开启中..." >> log.txt
        fi
        while :
        do
          # 创建一个匹配条件
          result=$(curl -X POST "$api_url2" \
            -H "X-Auth-Email: $email" \
            -H "X-Auth-Key: $api_key" \
            -H "Content-Type: application/json" \
            --data '[{ "expression": "(not cf.client.bot)" }]' --silent)

          if [ $(echo $result | jq -r '.success') == "true" ]; then # 如果创建成功
            # 保存匹配条件ID
            filterid=$(echo $result | jq -r '.result[].id')
            if [[ "$log" -eq 1 ]]; then
              echo "[`date`] 匹配条件创建成功" >> log.txt
            fi
          else
            if [[ "$log" -eq 1 ]]; then
              echo "[`date`] 错误代码002 匹配条件创建失败，尝试删除冲突匹配条件"
            fi
            filterid=$(echo $result | jq -r '.errors[].meta.id') # 获取导致冲突的匹配条件ID
            for i in $filterid
            do
              # 删除冲突的匹配条件
              result1=$(curl -X DELETE "$api_url2/$i" \
                -H "X-Auth-Email: $email" \
                -H "X-Auth-Key: $api_key" \
                -H "Content-Type: application/json" --silent)
            done

            # 如果冲突匹配条件删除成功
            if [ $(echo $result1 | jq -r '.success') ]; then
              if [[ "$log" -eq 1 ]]; then
                echo "[`date`] 冲突的匹配条件删除成功" >> log.txt
              fi
            else
              if [[ "$log" -eq 1 ]]; then
                echo "[`date`] 冲突的匹配条件删除失败" >> log.txt
              fi
            fi
          fi
          # 退出循环
          if [ $(echo $result | jq -r '.success') == "true" ]; then
            break
          fi
        done

        # 开启防火墙验证码
        result=$(curl -X POST "$api_url1" \
          -H "X-Auth-Email: $email" \
          -H "X-Auth-Key: $api_key" \
          -H "Content-Type: application/json" \
          --data "[{
            \"action\": \"challenge\",
            \"filter\": {
              \"id\": \"$filterid\",
              \"expression\": \"(not cf.client.bot)\"
            }
          }]" --silent)

        if [ $(echo $result | jq -r '.success') == "true" ]; then
            ruleid=$(echo $result | jq -r '.result[].id')
            echo "$filterid" > filterid.txt
            echo "$ruleid" > ruleid.txt
            if [[ "$log" -eq 1 ]]; then
              echo "[`date`] 验证码开启成功，规则id：$ruleid" >> log.txt
            fi
        fi
      fi
    fi
  fi
  sleep $interval
  clear
done
