$PowerSlimCmd="C:\PowerSlim\runSlimServer.cmd"
$CurrentUser=whoami

schtasks /Create /TN PowerSlim /SC ONSTART /TR $PowerSlimCmd /RL HIGHEST /F /RU $CurrentUser /RP 1
