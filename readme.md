# nTRAC - n-Track Recording Audio transCription

This script combines separate tracks of an audio recording to a mono file and optionally generates a transcript. It was originally made as a tool to transcribe the two channels of phone recordings from [FreePBX](https://www.freepbx.org), but it now work as a standalone tool and with 1, 2 or n channels (or tracks) as well.
Output files - recordings and transcripts - can be made available on external servers or at services such as Dropbox and various other cloud storage solutions.

## Requirements
- [Sox](http://sox.sourceforge.net) for handling sound files
- [Rclone](https://rclone.org) to exchange files with transcription services and storage providers
- Accounts at transcription services (optional)

## Installation

### FreePBX

1. Download `ntrac.sh` and `ntrac.config.example`, e.g. to `/usr/local/bin/`
2. Make `ntrac.sh` executable for user `asterisk`:
   `chown asterisk:asterisk /usr/local/bin/ntrac.sh`
   `chmod +x /usr/local/bin/ntrac.sh`
3. Make a copy of the configuration file and adjust it to your needs:
   `cp /usr/local/bin/ntrac.config.example /usr/local/bin/ntrac.config`
   `nano /usr/local/bin/ntrac.config`
4. To learn how to configure FreePBX to record calls in separate channels, see [FreePBX-config.md](FreePBX-config.md).
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
   - `google_rclone="Google:nTRAC"`
   If your Rclone remote is `Google:` and your bucket is `nTRAC`  
   - `google_key="AIzaSyDJ2pShrqUP84xCZmXOR453WyWVr-sfY3I"`
   Your API key  
   - `language_alt="'fr-FR', 'de-DE'"`
   Google can auto-detect the language. Provide alternatives to default language here (be careful with the quotation marks!). Using this, you can have multiple languages in one recording. (The default language can be set separately or passed to the script with a parameter, see below.)  

### [Auphonic](https://auphonic.com)

1. To use Auphonic for transcription, create an account and go to the [services page](https://auphonic.com/engine/services/). You'll need at least two services: one for file transfers, and another one for speech recognition.
2. Create one or two file transfer services, depending whether your output files should be stored in the same location as your input files. For incoming file transfers you must choose a service that is also [supported by Rclone](https://rclone.org/overview/).
3. On your local machine or PBX, configure Rclone for the same file transfer service. The idea is, that your machine uploads recordings using Rclone to a location where Auphonic picks them up. Make sure to do this using the same user that later executes nTRAC - e.g. on FreePBX the Asterisk user: `sudo -u asterisk rclone config`
4. On Auphonic, create a speech recognition service. You will also have to set up an account with that service. Please refer to the [Auphonic documentation](https://auphonic.com/help/web/services.html#automatic-speech-recognition-services)
5. Once again, navigate to the services page of your Auphonic account and find the UUIDs of the services you created.
6. Edit `ntrac.sh` to enter your Auphonic credentials
   - `auphonic_user="myusername"` and `auphonic_pass="myP@ssw0rd"`
   Your Auphonic login credentials  
   - `auphonic_rclone="Auphonic:"`
   Name of Rclone remote that is used to upload your recordings for Auphonic. (This can be the same Rclone remote that you use for `destination` (see below) or `google_rclone`)
   - `auphonic_in="FWT6XWKIO82r3EPqSsHgce"`              
   The UUID of the service for incoming file transfers. This must point to the same location as `auphonic_rclone`. Your system will use Rclone to upload the recordings e.g. to Dropbox or Google Drive. Auphonic will use this service to download the recordings from Dropbox/GDrive.
   - `auphonic_preset_multi=""` and/or `auphonic_preset_single=""`
   Optional, but strongly recommended. [Create a Multitrack Preset](https://auphonic.com/engine/multitrack/preset/) with two tracks - the first track should be for the local side i.e. outgoing audio, the second track for the remote side or incoming audio. This settings of the second track will be used by nTRAC for any additional tracks that you might add, say if you transcribe a 4-track recording.
   Add a Speech Recognition Service to your preset; all other settings are optional. Save the preset, and copy its UUID to nTRAC.
   Repeat with a [1-track preset](https://auphonic.com/engine/preset/), if you are intending to send single-track productions to Auphonic.
   - `auphonic_stt="Qw5wpWCyCiows98Edj8b49"`
   The UUID of the automatic speech recognition service. This will only be used if you opt to not use a preset, in which case it is mandatory.  
   - `auphonic_out=""`
   Optional and used only if no preset is defined. UUID of a service that Auphonic should use to transfer the results somewhere. This can be the same as `auphonic_in`. If set, the transcript and other files generated by Auphonic will NOT be saved locally.

Note: If you define a preset that uses an outgoing service, unprocessed input files will not be available to that service. However, if you additionally set `destination` (see below), all results and unprocessed input files will be copied there.

## Default Settings

Edit `ntrac.sh` to change the default settings. You can always override default settings by passing a parameter to the script, see Usage below.
- `auphonic=false`
  If `true` Auphonic transcription will always be triggered.
- `google=false`
  If both Google and Auphonic are `false` and neither service is called using a command line parameter, only a mono mix will be created.
- `language="en-US"`
  Default language for transcripts
- `delete_input_files=true`
  If true, input files will be deleted from local system (they will be copied to the output destination, though).
- `destination=""`
  - leave empty (or set to `dir`) to use directory of output file
  - set to e.g. `destination="/path/to/folder"` to use a writable folder on local system or
  - set to e.g. `destination="Dropbox:transcripts"` to use a folder on a Rclone remote called Dropbox

## Usage

`ntrac.sh [ -a | --auphonic ] [ -g | --google ] [ <-l | --language> <en-US | en-GB | de-DE |...> | --en-US | --en-GB | --de-DE... ] [ delete=<true | false> ] [ dest=</path/to/folder | RcloneRemote1:folder | dir> ] /path/to/channel_1.wav /path/to/channel_2.wav /path/to/channel_n.wav /path/to/output.wav`

### Parameters

If no parameters are given, only a mono-mix file is generated.
- `-a`, `--auphonic`                 
   use Auphonic for transcription
- `-g`, `--google`                       
   use Google for transcription
- `-l`, `--language`                     
   define transcription language. Must be followed by language code, e.g.`en-US`, `en-GB`, `de-DE`. For available languages at Google see [here](https://cloud.google.com/speech-to-text/docs/languages).
- `--en-US`, `--en-GB`, `--de-DE`...   
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
