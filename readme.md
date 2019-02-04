# nTRAC - n-Track Recording Audio transCription

This script combines separate tracks of an audio recording to a mono file and optionally generates a transcript. It was originally made as a tool to transcribe the two channels of phone recordings from [FreePBX](https://www.freepbx.org), but it now work as a standalone tool and with 1, 2 or n channels (or tracks) as well. 
Output files - recordings and transcripts - can be made available on external servers or at services such as Dropbox and various other cloud storage solutions.

## Requirements
- [Sox](http://sox.sourceforge.net) for handling sound files
- [Rclone](https://rclone.org) to exchange files with transcription services and storage providers
- Accounts at transcription services (optional)

## Installation

### FreePBX

1. Download `ntrac.sh`, e.g. to `/usr/local/bin/`
2. Make it executable for user `asterisk`: 
   `chown asterisk:asterisk /usr/local/bin/ntrac.sh`
   `chmod +x /usr/local/bin/ntrac.sh`
3. To learn how to configure FreePBX to record calls in separate channels, see [FreePBX-config.md](FreePBX-config.md).
### Other Systems

Just download and run.

## Transcription Services
nTRAC uses Google Cloud Platform or Auphonic to generate transcripts. Please familiarize yourself with their terms, conditions, and pricing.

### [Google Cloud Platform](https://cloud.google.com)
1. To use Google for transcription, create an account, go to the Console, and create a project.
2. Navigate to the API library and activate the Cloud Storage and Cloud Speech APIs for your project.
3. Navigate to Storage and create a bucket for your project
4. On your local machine or PBX, [configure Rclone for Google Cloud Storage](https://rclone.org/googlecloudstorage/), using the command
   `rclone config`. Make sure to do this using the same user that later executes nTRAC - e.g. on FreePBX the Asterisk user: `sudo -u asterisk rclone config `
   Use standard options in most cases, except when prompted for:
   - Access Control List for new objects -> "publicRead"
   - Use auto config? -> n
5. On the Google Cloud Storage console, [create an API key](https://console.cloud.google.com/apis/credentials) for your project

6. Edit `ntrac.sh` to enter your Google credentials
   - `GOOGLE_RCLONE="Google:nTRAC"`
   If your Rclone remote is `Google:` and your bucket is `nTRAC`  
   - `GOOGLE_KEY="AIzaSyDJ2pShrqUP84xCZmXOR453WyWVr-sfY3I"`
   Your API key  
   - `LANGUAGE_ALT="'fr-FR', 'de-DE'"`
   Google can auto-detect the language. Provide alternatives to default language here (be careful with the quotation marks!). Using this, you can have multiple languages in one recording. (The default language can be set separately or passed to the script with a parameter, see below.)  

### [Auphonic](https://auphonic.com)

1. To use Auphonic for transcription, create an account and go to the [services page](https://auphonic.com/engine/services/). You'll need at least two services: one for file transfers, and another one for speech recognition.
2. Create one or two file transfer services, depending whether your output files should be stored in the same location as your input files. For incoming file transfers you must choose a service that is also [supported by Rclone](https://rclone.org/overview/).
3. On your local machine or PBX, configure Rclone for the same file transfer service. The idea is, that your machine uploads recordings using Rclone to a location where Auphonic picks them up. Make sure to do this using the same user that later executes nTRAC - e.g. on FreePBX the Asterisk user: `sudo -u asterisk rclone config`
4. On Auphonic, create a speech recognition service. You will also have to set up an account with that service. Please refer to the [Auphonic documentation](https://auphonic.com/help/web/services.html#automatic-speech-recognition-services)
5. Once again, navigate to the services page of your Auphonic account and find the UUIDs of the services you created.
6. Edit `ntrac.sh` to enter your Auphonic credentials
   - `AUPHONIC_USER="myusername"` and `AUPHONIC_PASS="myP@ssw0rd"`
   Your Auphonic login credentials  
   - `AUPHONIC_RCLONE="Auphonic:"`
   Name of Rclone remote that is used to upload your recordings for Auphonic. (This can be the same Rclone remote that you use for `DESTINATION` (see below) or `GOOGLE_RCLONE`)
   - `AUPHONIC_IN="FWT6XWKIO82r3EPqSsHgce"`              
   The UUID of the service for incoming file transfers. This must point to the same location as `AUPHONIC_RCLONE`. Your system will use Rclone to upload the recordings e.g. to Dropbox or Google Drive. Auphonic will use this service to download the recordings from Dropbox/GDrive.
   - `AUPHONIC_PRESET_MULTI=""` and/or `AUPHONIC_PRESET_SINGLE=""`
   Optional, but strongly recommended. [Create a Multitrack Preset](https://auphonic.com/engine/multitrack/preset/) with two tracks - the first track should be for the local side i.e. outgoing audio, the second track for the remote side or incoming audio. This settings of the second track will be used by nTRAC for any additional tracks that you might add, say if you transcribe a 4-track recording.
   Add a Speech Recognition Service to your preset; all other settings are optional. Save the preset, and copy its UUID to nTRAC.
   Repeat with a [1-track preset](https://auphonic.com/engine/preset/), if you are intending to send single-track productions to Auphonic.
   - `AUPHONIC_STT="Qw5wpWCyCiows98Edj8b49"`
   The UUID of the automatic speech recognition service. This will only be used if you opt to not use a preset, in which case it is mandatory.  
   - `AUPHONIC_OUT=""`
   Optional and used only if no preset is defined. UUID of a service that Auphonic should use to transfer the results somewhere. This can be the same as `AUPHONIC_IN`. If set, the transcript and other files generated by Auphonic will NOT be saved locally.

Note: If you define a preset that uses an outgoing service, unprocessed input files will not be available to that service. However, if you additionally set `DESTINATION` (see below), all results and unprocessed input files will be copied there.

## Default Settings

Edit `ntrac.sh` to change the default settings. You can always override default settings by passing a parameter to the script, see Usage below.
- `AUPHONIC=false`
  If `true` Auphonic transcription will always be triggered.
- `GOOGLE=false`
  If both Google and Auphonic are `false` and neither service is called using a command line parameter, only a mono mix will be created.
- `LANGUAGE="en-US"`
  Default language for transcripts
- `DELETE_INPUT_FILES=true`
  If true, input files will be deleted from local system (they will be copied to the output destination, though).
- `DESTINATION=""`
  - leave empty (or set to `dir`) to use directory of output file
  - set to e.g. `DESTINATION="/path/to/folder"` to use a writable folder on local system or 
  - set to e.g. `DESTINATION="Dropbox:transcripts"` to use a folder on a Rclone remote called Dropbox

## Usage

`ntrac.sh [ -a | --auphonic ] [ -g | --google ] [ <-l | --language> <en-EN | en-UK | de-DE |...> | --en-EN | --en-UK | --de-DE... ] [ delete=<true | false> ] [ dest=</path/to/folder | RcloneRemote1:folder | dir> ] /path/to/channel_1.wav /path/to/channel_2.wav /path/to/channel_n.wav /path/to/output.wav`

### Parameters

If no parameters are given, only a mono-mix file is generated.
- `-a`, `--auphonic`                 
   use Auphonic for transcription
- `-g`, `--google`                       
   use Google for transcription
- `-l`, `--language`                     
   define transcription language. Must be followed by language code, e.g.`en-EN`, `en-UK`, `de-DE`. For available languages at Google see [here](https://cloud.google.com/speech-to-text/docs/languages).
- `--en-EN`, `--en-UK`, `--de-DE`...   
   alternative definition of transcription language 
- `delete=true`  
   Input files will be deleted from source directory. They will be copied to the output directory, though. 
- `delete=false`  
   Input files will be kept at source directory and copied to output directory.
- `dest=/path/to/folder`  
   Results will be available at this local folder.
- `dest=RcloneRemote1:folder`  
   Results will be moved to `folder` at `RcloneRemote1:`
- `dest=dir`  
   Results will be available at the folder of output.wav (see below)
- `/path/to/channel_1.wav`  
   The first file provided will be considered the outgoing or local leg of the conversation.
- `/path/to/channel_2.wav`  
   The second file and all subsequent files provided will be considered the incoming or remote leg(s) of the conversation.
- `/path/to/output.wav`  
   The last file provided will be considered the output file of the script. The path will also be used for other output files, such as transcripts.  

## Credits

Created by Thomas Reintjes 2019
Based on

- 2wav2mp3 - 2005 05 23 dietmar zlabinger http://www.zlabinger.at/asterisk
- Asterisk voicemail attachment conversion script - Jason Klein, Ward Mundy & Associates LLC, et al
