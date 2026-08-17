@echo off
setlocal

set ZIP_NAME=heapvlc.zip

if exist %ZIP_NAME% del %ZIP_NAME%

echo Creating ZIP for heapvlc: %ZIP_NAME%
powershell -Command "Compress-Archive -Path * -DestinationPath %ZIP_NAME%"