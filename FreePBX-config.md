# FreePBX Configuration
How to make FreePBX record the two legs of a conversation separately and pass the files to 2CRT for further processing.

## On Demand Recordings
To automatically transcribe all on-demand recordings (recordings that you initiate by dialing `*1` during a call), paste the following into the file `/etc/asterisk/extensions_override_freepbx.conf`:
``` 
[macro-one-touch-record]
include => macro-one-touch-record-custom
exten => s,n,Set(ONETOUCH_REC_SCRIPT_STATUS=)
exten => s,n,Set(MONITOR_EXEC_ARGS=--google --en_US)
exten => s,n,System(${AMPBIN}/one_touch_record.php "${CHANNEL(name)}")
exten => s,n,Noop(ONETOUCH_REC_SCRIPT_STATUS: [${ONETOUCH_REC_SCRIPT_STATUS}])
exten => s,n,Noop(REC_STATUS: [${REC_STATUS}])
exten => s,n,GotoIf($["${ONETOUCH_REC_SCRIPT_STATUS:0:6}"="DENIED"]?denied)
exten => s,n,ExecIf($["${REC_STATUS}"="STOPPED"]?Playback(beep&beep))
exten => s,n,GotoIf($["${REC_STATUS}"="STOPPED"]?end)
exten => s,n,GotoIf($["${REC_STATUS}"="RECORDING"]?startrec)
exten => s,n(startrec),Monitor(wav,${MIXMON_DIR}${YEAR}/${MONTH}/${DAY}/${CALLFILENAME},m)
exten => s,n,ExecIf($["${REC_STATUS}"="RECORDING"]?Playback(beep))
exten => s,n(denied),ExecIf($["${ONETOUCH_REC_SCRIPT_STATUS:0:6}"="DENIED"]?Playback(access-denied))
exten => s,n(end),MacroExit()

;--== end of [macro-one-touch-record] ==--;
```
In line 4, you can modify or add the parameters to your liking. The three files (channel 1, channel 2, output) will be passed to the script automatically.

Next, edit the file `/etc/asterisk/globals_custom.conf` and add the line:
`MONITOR_EXEC=/usr/local/bin/2crt.sh`

Lastly, issue the command `service amportal restart` to make the system aware of your changes.

Tested with Incredible PBX 13-13