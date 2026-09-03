@echo off
chcp 65001 >nul 2>&1
title Network Diagnostic Tool

set OUTPUT=%USERPROFILE%\Desktop\network_diag.txt
set "PHONE_TARGET_IP="
set /p "PHONE_TARGET_IP=Enter phone IP address (for example 10.200.16.15): "
set "PHONE_TARGET_PORT=8080"
set /p "PHONE_TARGET_PORT=Enter phone service port [8080]: "
if not defined PHONE_TARGET_PORT set "PHONE_TARGET_PORT=8080"

echo =================================================== > "%OUTPUT%"
echo Network Diagnostic Report > "%OUTPUT%"
echo Generated at: %date% %time% >> "%OUTPUT%"
echo Computer name: %COMPUTERNAME% >> "%OUTPUT%"
echo User: %USERNAME% >> "%OUTPUT%"
echo =================================================== >> "%OUTPUT%"

echo [1/10] ipconfig /all >> "%OUTPUT%"
echo --- [1] FULL IP CONFIGURATION --- >> "%OUTPUT%"
ipconfig /all >> "%OUTPUT%" 2>&1

echo [2/10] route print >> "%OUTPUT%"
echo --- [2] ROUTING TABLE --- >> "%OUTPUT%"
route print >> "%OUTPUT%" 2>&1

echo [3/10] netstat -ano >> "%OUTPUT%"
echo --- [3] ALL ACTIVE CONNECTIONS AND PORTS --- >> "%OUTPUT%"
netstat -ano >> "%OUTPUT%" 2>&1

echo [4/10] netstat listening ports >> "%OUTPUT%"
echo --- [4] LISTENING PORTS ONLY --- >> "%OUTPUT%"
netstat -an | findstr LISTENING >> "%OUTPUT%" 2>&1

echo [5/10] netsh wlan show interfaces >> "%OUTPUT%"
echo --- [5] WI-FI INTERFACE INFO --- >> "%OUTPUT%"
netsh wlan show interfaces >> "%OUTPUT%" 2>&1

echo [6/10] netsh wlan show all >> "%OUTPUT%"
echo --- [6] ALL WI-FI PROFILES AND INFO --- >> "%OUTPUT%"
netsh wlan show all >> "%OUTPUT%" 2>&1

echo [7/10] firewall state >> "%OUTPUT%"
echo --- [7] WINDOWS FIREWALL STATE --- >> "%OUTPUT%"
netsh advfirewall show allprofiles >> "%OUTPUT%" 2>&1

echo [8/10] arp table >> "%OUTPUT%"
echo --- [8] ARP TABLE --- >> "%OUTPUT%"
arp -a >> "%OUTPUT%" 2>&1

echo [9/10] DNS test >> "%OUTPUT%"
echo --- [9] DNS RESOLUTION TEST --- >> "%OUTPUT%"
nslookup www.baidu.com >> "%OUTPUT%" 2>&1

echo [10/11] internet connectivity >> "%OUTPUT%"
echo --- [10] INTERNET CONNECTIVITY (PowerShell) --- >> "%OUTPUT%"
powershell -NoProfile -Command "Test-NetConnection" >> "%OUTPUT%" 2>&1

echo [11/11] phone service connectivity >> "%OUTPUT%"
echo --- [11] PHONE SERVICE CONNECTIVITY --- >> "%OUTPUT%"
if not defined PHONE_TARGET_IP (
  echo SKIPPED: phone IP was not provided. >> "%OUTPUT%"
) else (
  echo Target: %PHONE_TARGET_IP%:%PHONE_TARGET_PORT% >> "%OUTPUT%"
  powershell -NoProfile -Command "$ip=$env:PHONE_TARGET_IP; $port=[int]$env:PHONE_TARGET_PORT; Write-Output '--- ICMP ---'; Test-Connection -ComputerName $ip -Count 4; Write-Output '--- TCP ---'; Test-NetConnection -ComputerName $ip -Port $port -InformationLevel Detailed; Write-Output '--- ARP ---'; arp -a" >> "%OUTPUT%" 2>&1
)

echo. >> "%OUTPUT%"
echo =================================================== >> "%OUTPUT%"
echo PLEASE ALSO PROVIDE THE FOLLOWING MANUALLY: >> "%OUTPUT%"
echo 1. Phone OS: iOS / Android and version >> "%OUTPUT%"
echo 2. Wi-Fi name the phone is connected to >> "%OUTPUT%"
echo 3. Phone IP address (from Wi-Fi settings) >> "%OUTPUT%"
echo 4. The port your app uses (e.g. 8080) >> "%OUTPUT%"
echo 5. The full URL you typed in the browser >> "%OUTPUT%"
echo Target entered for this report: %PHONE_TARGET_IP%:%PHONE_TARGET_PORT% >> "%OUTPUT%"
echo =================================================== >> "%OUTPUT%"

echo.
echo ===================================================
echo  Diagnostic complete!
echo  File saved to Desktop: network_diag.txt
echo  Please send this file to the developer.
echo ===================================================
echo.
pause
