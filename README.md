# x-ui-scripts

This repository contains some useful scripts for x-ui and 3x-ui.

# Scripts

## Manual Build [3x-ui](https://github.com/MHSanaei/3x-ui)

```sh
bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)
```

## Install [Warp](https://gitlab.com/fscarmen/warp) (on socks5 proxy) for 3x-ui

```sh
bash <(curl -sSL https://raw.githubusercontent.com/RockBlack-VPN/x-ui-warp/main/install_warp_proxy.sh)
```
Указываем порт 40000

# Настройка Warp на 3x-ui
Создать входящее подключение vless и включить `Sniffing`

![Screenshot](https://rockblack.pro/images/warp/Screenshot_2.jpg)

После того как создали подключнеи vless, перейти в `Настройки Xray / Исходящее соедиение` нажать WARP, Создать

![Screenshot](https://rockblack.pro/images/warp/Screenshot_3.jpg)

### options

- `-y` => Accept default values
- `-f` => Force reinstall Warp Socks5 Proxy (WireProxy)

### commands

- `warp u` => Uninstall Warp
- `warp a` => Change Warp Account Type (free, plus, etc.)
- `warp y` => Turn on/off WireProxy

### Notes

- **To use IPv4 for routing warp:**
  1. Go to Panel > Settings > Xray Configurations > Complete Template
  2. Find the object with tag `WARP` in outbounds:
     ```json
     {
       "tag": "WARP",
       "protocol": "socks",
       "settings": {
         "servers": [
           {
             "address": "127.0.0.1",
             "port": 40000
           }
         ]
       }
     }
     ```
  3. Replace it with the following json object:
     ```json
     {
       "tag": "WARP-socks5",
       "protocol": "socks",
       "settings": {
         "servers": [
           {
             "address": "127.0.0.1",
             "port": 40000
           }
         ]
       }
     },
     {
       "tag":"WARP",
       "protocol":"freedom",
       "proxySettings":{
         "tag":"WARP-socks5"
       },
       "settings":{
         "domainStrategy":"UseIPv4"
       }
     }
     ```
- **To use IPv6 for routing warp:**
  - Follow the same steps as for IPv4, replacing `UseIPv4` with `UseIPv6`
