#!/bin/bash
#
# nTRAC: n-Track Recording Audio transCription
# converts two legs of a call or any multi-track recording into one mono-mixdown and generates a transcript
#
# For important setup instructions see readme.md
#
# based on
# - 2wav2mp3 - 2005 05 23 dietmar zlabinger http://www.zlabinger.at/asterisk
# - Asterisk voicemail attachment conversion script - Jason Klein, Ward Mundy & Associates LLC, et al
#
# Revision history :
# 31. Jan 2019 - v0.9 - Creation by Thomas Reintjes
#
#
##############################################################################################################################################

#### SETTINGS ####

. ntrac.config

#
############ NO EDITS BELOW THIS LINE ########################################################################################################

if [ "$debug_mode" = true ] ; then
  set -x
  exec 3>&1 4>&2
  trap 'exec 2>&4 1>&3' 0 1 2 3
  exec 1>"$log_file" 2>&1
fi

# don't care if strings in "case" or [[...]] are uppercase or lowercase
shopt -s nocasematch
#
####################### FUNCTIONS ########################################################
#
# help and exit
help_and_exit() {
  local retval=${1:-1}
  cat <<EOF
${0##*/} [ -a | --auphonic ] [ -g | --google ] [ -l < en-EN | en-UK | de-DE | ...> | --language < en-EN | en-UK | de-DE |...> | --en-EN | --en-UK | --de-DE... ] [ delete=< true | false > ] [ dest=< /path/to/dir | RcloneRemote1:path/to/dir | dir > ] /path/to/outgoing.wav /path/to/incoming.wav /path/to/output.wav

If no parameters are given, only a mono-mix file is generated.
EOF
  exit "$retval"
}

# function to move files to output location
# output <copy|move> file
output () {
 if [[ $DESTINATION == /** ]] ; then
  local NEWFILE="$DESTINATION/$(basename -- "$2")"
  if [ "$NEWFILE" != "$2" ] ; then 
    if [[ "$1" == copy ]] ; then
      mkdir -p "$DESTINATION" && cp "$2" "$NEWFILE"
    elif [[ "$1" == move ]] ; then
      mkdir -p "$DESTINATION" && mv "$2" "$NEWFILE"
    else
      return 1   # something's wrong
    fi
  else
    return 0     # all good
  fi
 else
  rclone "$1" "$2" "$DESTINATION"
 fi
}

# cleanup
cleanup() {
if [[ "$1" == google ]] ; then
  rclone delete "$GOOGLE_RCLONE/$BASENAME-nchannel.flac"
fi
if [[ "$1" == auphonic ]] && [ "$AUPHONIC_RCLONE" != "$DESTINATION" ] && [ "$AUPHONIC_IN" != "$AUPHONIC_OUT" ] ; then
  for filename in "${input_filenames[@]}" ; do
    rclone delete "$AUPHONIC_RCLONE/$filename"
  done
fi
if [[ "$1" == all ]] && [ "$DELETE_INPUT_FILES" = true ] && [[ "$DESTINATION" != "$OUTPUT_DIR" ]] ; then
  for inputfile in "${input_files[@]}" ; do
    rm "$inputfile" ;
  done
fi
}
#
####################### VARIABLES ########################################################
#
# command line variables
input_files=( )

while (( $# )); do
  case $1 in
    -a|--auphonic) AUPHONIC=true ;;
    -g|--google) GOOGLE=true ;;
    -l|--language) LANGUAGE=$2; shift ;;
    --[abcdefghijklmnopqstuvwxyz][abcdefghijklmnopqstuvwxyz]-[ABCDEFGHIJKLMNOPQRSTUVWXYZ][ABCDEFGHIJKLMNOPQRSTUVWXYZ]) LANGUAGE=${1:2} ;;
    delete=true) DELETE_INPUT_FILES=true ;;
    delete=false) DELETE_INPUT_FILES=false ;;
    dest=/**) DESTINATION="${1#*=}" ;;
    dest=[a-zA-Z]*:) DESTINATION="${1#*=}" ;;
    dest=[a-zA-Z]*:[a-zA-Z]*/**) DESTINATION="${1#*=}" ;;
    dest=dir) DESTINATION="${1#*=}" ;;
    -h|--help) help_and_exit 0 ;;
    -*)        printf 'Unknown option: %q\n\n' "$1"
               help_and_exit 1 ;;
    *)         input_files+=( "$1" ) ;;
  esac
  shift
done

MIX="${input_files[@]: -1}"                   # last file = output file
TRACKS=$((${#input_files[@]}-1))              # number of tracks (out/local/host + in/remotes/guests)
unset "input_files[${#input_files[@]}-1]"     # remove MIX from array

# more variables
OUTPUT_DIR="${MIX%/*}"                        # e.g. /var/spool/asterisk/monitor/year/month/day
FILENAME="${MIX##*/}"                         # e.g. recording1234.wav
BASENAME="${FILENAME%.*}"                     # e.g. recording1234
EXTENSION="${FILENAME##*.}"                   # e.g. wav

# all filenames
input_filenames=( )
for inputfile in "${input_files[@]}" ; do
  input_filenames+=( "$(basename -- "$inputfile")" ) 
done

# if last file was passed without a path, try to fix it
if [[ $OUTPUT_DIR != /** ]] ; then
  if [[ $DESTINATION == /** ]] ; then
    OUTPUT_DIR="$DESTINATION"
  else
    equalinputfolders=true
    inputfolder="$(dirname -- "${input_files[0]}")"
    for inputfile in "${input_files[@]}"; do
      if [[ "$inputfolder" != "$(dirname -- "$inputfile")" ]] ; then
        equalinputfolders=false
        break
      fi
    done
    if [ "$equalinputfolders" = true ] ; then
    # if all input files are in the same directory, try using that directory
      OUTPUT_DIR="$(dirname -- "${input_files[0]}")"
      MIX="$OUTPUT_DIR/$FILENAME"
    else
      printf 'No output location specified or invalid\n\n'
      help_and_exit 1
    fi
  fi
fi

if [[ $DESTINATION == dir || $DESTINATION == "" ]] ; then
  DESTINATION="$OUTPUT_DIR"
else
  # remove trailing slash
  DESTINATION="${DESTINATION%/}"
fi
#
####################### SOX ##############################################################
#
# copy input files to output destination
for inputfile in "${input_files[@]}" ; do
  output copy "$inputfile"
done

if [ $TRACKS -gt 1 ] ; then
# create mono mixdown
  $SOX -m "${input_files[@]}" "$MIX"
# rename mono-mix and move to destination
  MIX_TMP="$OUTPUT_DIR/$BASENAME-mix.$EXTENSION"
  cp "$MIX" "$MIX_TMP" && output move "$MIX_TMP"
else
  cp "${input_files[0]}" "$MIX" && output copy "$MIX"
fi

# make mono mix available to FreePBX
if [ "$FREEPBX" = true ] ; then
  if [ "$(dirname -- "${input_files[0]}")" != "$OUTPUT_DIR" ] ; then
    mv "$MIX" "$(dirname -- "${input_files[0]}")/$FILENAME"
  fi
else
  # if not for FreePBX, mono-mix is not needed anymore
  rm "$MIX"
fi
#
####################### Google transcription #############################################
#
if $GOOGLE ; then

  TRANSCRIPT="$OUTPUT_DIR/$BASENAME-$LANGUAGE.txt"
  MIX_nchannel="$OUTPUT_DIR/$BASENAME-nchannel.flac"

  if [ "$TRACKS" -gt 1 ] ; then
    googlefiles=()
    for i in "${!input_files[@]}" ; do
    # create mono versions of input files
      $SOX "${input_files[$i]}" --channels 1 "$OUTPUT_DIR/googlemono$i.flac"
      googlefiles[$i]="$OUTPUT_DIR/googlemono$i.flac"
    done
    # google requires a multi-channel file with all input files combined
    $SOX -M "${googlefiles[@]}" "$MIX_nchannel"
    for googlefile in "${googlefiles[@]}" ; do
    # delete mono versions
      rm "$googlefile"
    done
  else
    # create mono-version of only input file
    $SOX "${input_files[0]}" --channels 1 "$MIX_nchannel"
  fi

  SAMPLERATE=$(soxi -r "$MIX_nchannel")
  
  test -r "$MIX_nchannel" && rclone move "$MIX_nchannel" "$GOOGLE_RCLONE"

  GOOGLE_BUCKET="${GOOGLE_RCLONE#*:}"

  JSON=$(curl -X POST \
     -H "Content-Type: application/json; charset=utf-8" \
     --data "{
  'config': {
    'encoding': 'FLAC',
    'sample_rate_hertz': '$SAMPLERATE',
    'languageCode': '$LANGUAGE',
    'audioChannelCount': '$TRACKS',
    'enableSeparateRecognitionPerChannel': true,
    'alternativeLanguageCodes': [$LANGUAGE_ALT],
    'enableAutomaticPunctuation': true
  },
  'audio': {
    'uri': 'gs://$GOOGLE_BUCKET/$BASENAME-nchannel.flac'
  }
}" "https://speech.googleapis.com/v1p1beta1/speech:longrunningrecognize?key=$GOOGLE_KEY")

# extract operation ID from json
  if [[ $JSON == *"error"* ]] ; then
    printf "%s" "$JSON" > "$TRANSCRIPT"
    output move "$TRANSCRIPT"
    printf 'Google transcription produced an error\n\n'
    help_and_exit 1
  else
    GOOGLE_OPERATION=$( grep name -m 1 <<< "$JSON" | sed 's#^.*"name": "##g' | sed 's#"$##g')
  fi

# check once every 30 seconds, if operation is done. Abort after checking set number of times
  TIMER=$(($TIMEOUT * 2))
    until [[ $JSON == *"\"done\": true"* ]] ; do
    if [ $TIMER -gt 0 ]; then
      sleep 30
      JSON=$(curl -H "Content-Type: application/json; charset=utf-8" "https://speech.googleapis.com/v1/operations/$GOOGLE_OPERATION?key=$GOOGLE_KEY")
      let "TIMER-=1"
    else
      printf 'Google transcription timed out\n\n'
      cleanup google
      help_and_exit 1
      break
    fi
  done

# extract transcript from json  
# 1. swap transcript and channelTag sections
  SEDMAGIC="grep -E 'transcript|channelTag' <<< '$JSON' | \
 sed 'N;    
 s/\(.*transcript.*\)\n\(.*channelTag.*\)/\2\
\1/' | \
 sed "
  for (( i=1; i <= $TRACKS; i++ ));
# 2. check if consecutive channelTags are equal, only keep the first one 
  do
  SEDMAGIC+=" -e '
   /channelTag"'"'": "$i"/{
   x
    /channelTag"'"'": "$i"/!{
    x
    h
    b
    }
   x
   d
   }
   '"
  done
# 3. replace channelTags with names
 SEDMAGIC+=" | sed -e 's/ *"'"'"channelTag"'"'": 1,/LOCAL:\\
/g'"

  for (( i=2; i <= ${TRACKS}; i++ ));
  do
  SEDMAGIC+=" -e 's/ *"'"'"channelTag"'"'": "$i",/REMOTE "$((i - 1))":\\
/g'"
  done
  SEDMAGIC+=" -e 's/ *"'"'"transcript"'"'": "'"'" *//g' -e 's/"'"'",$//g'"
  
  eval "$SEDMAGIC" > "$TRANSCRIPT"
  output move "$TRANSCRIPT"

  cleanup google
fi
# done Google transcription
#
####################### Auphonic transcription ###########################################
#
if $AUPHONIC ; then
  auphonic_error_check() {
    if [[ $JSON == *"\"status_string\": \"Error\""* || $JSON == *"DOCTYPE html"* ]] ; then
      ERRORMSG="$OUTPUT_DIR/$BASENAME-ERROR.txt"
      echo "$JSON" > "$ERRORMSG"
      output move "$ERRORMSG"
      printf 'Auphonic transcription produced an error\n\n'
      cleanup auphonic
      help_and_exit 1
    else
      return 0
    fi
  }
  
  for inputfile in "${input_files[@]}" ; do
    rclone copy "$inputfile" "$AUPHONIC_RCLONE"
  done
   
  if [ "$TRACKS" -eq 1 ] ; then
    if [ -n "$AUPHONIC_PRESET_SINGLE" ] ; then
      # query Auphonic for preset details
      JSON=$(curl https://auphonic.com/api/preset/$AUPHONIC_PRESET_SINGLE.json -u $AUPHONIC_USER:$AUPHONIC_PASS)
      # check if outgoing services are defined or if results should be downloaded later
      DOWNLOAD_FLAG="$(grep 'outgoing_services' <<< "$JSON" | grep '\]')"
        
      JSON=$(curl -X POST -H "Content-Type: application/json" \
         https://auphonic.com/api/productions.json \
         -u $AUPHONIC_USER:$AUPHONIC_PASS \
         -d '{
                "preset": "'"$AUPHONIC_PRESET_SINGLE"'",
                "metadata": { "title": "'"$BASENAME"'" },
                "input_file": "'"${input_filenames[0]}"'",
                "service": "'"$AUPHONIC_IN"'"
             }')
    else
      JSON=$(curl -X POST -H "Content-Type: application/json" \
        https://auphonic.com/api/productions.json \
        -u $AUPHONIC_USER:$AUPHONIC_PASS \
        -d '{
            "metadata": { "title": "'"$BASENAME"'"},
            "output_basename": "'"$BASENAME"'-'"$LANGUAGE"'",
            "input_file": "'"${input_filenames[0]}"'",
            "service": "'"$AUPHONIC_IN"'",
            "output_files": [{"format": "wav", "filename": "'"$BASENAME"'-mix_filtered.wav"}],
            "algorithms": {
              "hipfilter": false, "leveler": false,
              "normloudness": false, "denoise": false
            },
            "speech_recognition": {
              "uuid": "'"$AUPHONIC_STT"'",
              "language": "'"$LANGUAGE"'"
              }
         }')
    fi      
  else 
    # tracks > 1
    # arrays for Auphonic production parameters
    declare -a track_1_parameters=(false '"auto"' false 0 '"LOCAL"')
    # array: 0:hipfilter 1:"backforeground" 2:denoise 3:denoiseamount 4:"id"
    declare -a track_2_parameters=(false '"auto"' false 0 '"REMOTE"')
    
    if [ -n "$AUPHONIC_PRESET_MULTI" ] ; then
      # query Auphonic for preset details
      JSON=$(curl https://auphonic.com/api/preset/$AUPHONIC_PRESET_MULTI.json -u $AUPHONIC_USER:$AUPHONIC_PASS)
      # check if outgoing services are defined or if results should be downloaded later
      DOWNLOAD_FLAG="$( grep 'outgoing_services' <<< "$JSON" | grep '\]')"

      if [ "$TRACKS" -eq 2 ] ; then
        # extract track IDs (names) from preset
        track_1_parameters[4]=`cat $JSON | grep '"id":' -m 1 | sed 's#^.*"id": "##g' | sed 's#", $##g'`
        track_2_parameters[4]=`cat $JSON | grep '"id":' -m 2 | tail -n1 | sed 's#^.*"id": "##g' | sed 's#", $##g'`
      
        JSON=$(curl -X POST -H "Content-Type: application/json" \
         https://auphonic.com/api/productions.json \
         -u $AUPHONIC_USER:$AUPHONIC_PASS \
         -d '{
                "preset": "'"$AUPHONIC_PRESET_MULTI"'",
                "metadata": { "title": "'"$BASENAME"'" },
                "multi_input_files": [
                  {
                  "type": "multitrack", "id": "'"${track_1_parameters[4]}"'",
                  "service": "'"$AUPHONIC_IN"'",
                  "input_file": "'"${input_filenames[0]}"'"
                  },
                  {
                  "type": "multitrack", "id": "'"${track_2_parameters[4]}"'",
                  "service": "'"$AUPHONIC_IN"'",
                  "input_file": "'"${input_filenames[1]}"'"
                  }
                ]
             }') 
      else
        # tracks > 2
        # build a template for tracks from preset
        tracknumber=0
        openbrackets=0
        track_template=( )

        while IFS='' read -r line || [[ -n "$line" ]] ; do
          if [[ -n $(grep '{' <<< "$line") ]] ; then
            let "openbrackets+=1"
          elif [[ -n $(grep '}' <<< "$line") ]] ; then
            let "openbrackets-=1"
          fi
          if [ "$tracknumber" = 0 ] && [[ -n $(grep 'multi_input_files' <<< "$line") ]] ; then
            tracknumber=1
          elif [ "$tracknumber" -gt 0 ] && [ "$tracknumber" -le 2 ] && [ "$openbrackets" -ge 4 ] ; then
            track_template[$tracknumber]+="$line""
            "
          elif [ "$tracknumber" -gt 0 ] && [ "$tracknumber" -le 2 ] && [ "$openbrackets" -lt 4 ] ; then
            # last line of track
            track_template[$tracknumber]+="$(sed 's#},#}#g' <<< $line)""
              "
            let "tracknumber+=1"
          fi
        done <<< "$JSON"
        
  	    j=0
        for parameter in "hipfilter" "backforeground" "denoise" "denoiseamount" "id" ; do     
        # getting the actual parameters for track 1 and 2
            track_1_parameters[$j]=$(grep -m 1 $parameter <<< "${track_template[1]}" | sed 's#.*"'"$parameter"'": ##g' | sed 's#",#"#g' | sed 's#, $##g' )
            track_2_parameters[$j]=$(grep -m 1 $parameter <<< "${track_template[2]}" | sed 's#.*"'"$parameter"'": ##g' | sed 's#",#"#g' | sed 's#, $##g' )
            let "j+=1"
        done
   
        AUPHONIC_TRACK_ADD="           
                  {
                  -insert_quotes-type-insert_quotes-: -insert_quotes-multitrack-insert_quotes-, -insert_quotes-id-insert_quotes-: ${track_1_parameters[4]},
                  -insert_quotes-service-insert_quotes-: -insert_quotes-$AUPHONIC_IN-insert_quotes-,
                  -insert_quotes-input_file-insert_quotes-: -insert_quotes-${input_filenames[0]}-insert_quotes-,
                  -insert_quotes-algorithms-insert_quotes-: {-insert_quotes-hipfilter-insert_quotes-: ${track_1_parameters[0]}, -insert_quotes-backforeground-insert_quotes-: ${track_1_parameters[1]}, -insert_quotes-denoise-insert_quotes-: ${track_1_parameters[2]}, -insert_quotes-denoiseamount-insert_quotes-: ${track_1_parameters[3]}}
                  },"
        for (( i=1; i < ${TRACKS}; i++ )); do
          AUPHONIC_TRACK_ADD+="           
                  {
                  -insert_quotes-type-insert_quotes-: -insert_quotes-multitrack-insert_quotes-, -insert_quotes-id-insert_quotes-: ${track_2_parameters[4]%\"*} $(($i+1))-insert_quotes-,
                  -insert_quotes-service-insert_quotes-: -insert_quotes-$AUPHONIC_IN-insert_quotes-,
                  -insert_quotes-input_file-insert_quotes-: -insert_quotes-${input_filenames[$i]}-insert_quotes-,
                  -insert_quotes-algorithms-insert_quotes-: {-insert_quotes-hipfilter-insert_quotes-: ${track_2_parameters[0]}, -insert_quotes-backforeground-insert_quotes-: ${track_2_parameters[1]}, -insert_quotes-denoise-insert_quotes-: ${track_2_parameters[2]}, -insert_quotes-denoiseamount-insert_quotes-: ${track_2_parameters[3]}}
                  },"
        done
   
        AUPHONIC_TRACK_ADD=$(sed 's#-insert_quotes-#"#g' <<< "$AUPHONIC_TRACK_ADD" | sed 's#\: " #\: "#g' | sed 's# ",#",#g' | sed 's#},$#}#g')
   
        JSON=$(curl -X POST -H "Content-Type: application/json" \
         https://auphonic.com/api/productions.json \
         -u $AUPHONIC_USER:$AUPHONIC_PASS \
         -d '{
                "preset": "'"$AUPHONIC_PRESET_MULTI"'",
                "metadata": { "title": "'"$BASENAME"'" },
                "output_basename": "'"$BASENAME"'-'"$LANGUAGE"'",
                "multi_input_files": [
                  '"$AUPHONIC_TRACK_ADD"'
                ]
             }')     
      fi  # <-- tracks =2 / >2
    else
      # no multi preset       
      AUPHONIC_TRACK_ADD="           
                {
                -insert_quotes-type-insert_quotes-: -insert_quotes-multitrack-insert_quotes-, -insert_quotes-id-insert_quotes-: -insert_quotes-Local-insert_quotes-,
                -insert_quotes-service-insert_quotes-: -insert_quotes-$AUPHONIC_IN-insert_quotes-,
                -insert_quotes-input_file-insert_quotes-: -insert_quotes-${input_filenames[0]}-insert_quotes-,
                -insert_quotes-algorithms-insert_quotes-: {-insert_quotes-hipfilter-insert_quotes-: false, -insert_quotes-denoise-insert_quotes-: false}
                },"
      for (( i=1; i < ${TRACKS}; i++ )); do
        AUPHONIC_TRACK_ADD+="           
                {
                -insert_quotes-type-insert_quotes-: -insert_quotes-multitrack-insert_quotes-, -insert_quotes-id-insert_quotes-: -insert_quotes-Remote $i-insert_quotes-,
                -insert_quotes-service-insert_quotes-: -insert_quotes-$AUPHONIC_IN-insert_quotes-,
                -insert_quotes-input_file-insert_quotes-: -insert_quotes-${input_filenames[$i]}-insert_quotes-,
                -insert_quotes-algorithms-insert_quotes-: {-insert_quotes-hipfilter-insert_quotes-: false, -insert_quotes-denoise-insert_quotes-: false}
                },"
      done
   
      AUPHONIC_TRACK_ADD=$(sed 's#-insert_quotes-#"#g' <<< "$AUPHONIC_TRACK_ADD" | sed 's#\: " #\: "#g' | sed 's# ",#",#g' | sed 's#},$#}#g')
      
      JSON=$(curl -X POST -H "Content-Type: application/json" \
       https://auphonic.com/api/productions.json \
       -u $AUPHONIC_USER:$AUPHONIC_PASS \
       -d '{
              "metadata": { "title": "'"$BASENAME"'" },
              "output_basename": "'"$BASENAME"'-'"$LANGUAGE"'",
              "output_files": [{"format": "wav", "filename": "'"$BASENAME"'-mix_filtered.wav"}],
              "multi_input_files": [
                '"$AUPHONIC_TRACK_ADD"'
              ],
              "speech_recognition": {
                "uuid": "'"$AUPHONIC_STT"'",
                "language": "'"$LANGUAGE"'"
                },
              "algorithms": {
                "leveler": false,
                "crossgate": true,
                "gate": false
               },
              "is_multitrack": true
           }')    
    fi # <-- preset exists
  fi # <-- tracks > 1

  auphonic_error_check
  # extract production ID from response
  UUID=$(grep uuid -m 1 <<< "$JSON" | sed 's#^.*"uuid": "##g' | sed 's#", $##g')
  
  # manage file output for no-preset productions
  if [[ "$TRACKS" -eq 1 && -z "$AUPHONIC_PRESET_SINGLE" ]] || [[ "$TRACKS" -gt 1 && -z "$AUPHONIC_PRESET_MULTI" ]] ; then
    if [ -n "$AUPHONIC_OUT" ] ; then
      # if set, tell Auphonic to move output files to destination
      curl -H "Content-Type: application/json" -X POST \
       https://auphonic.com/api/production/$UUID/outgoing_services.json \
       -u $AUPHONIC_USER:$AUPHONIC_PASS \
       -d '[{"uuid": "'"$AUPHONIC_OUT"'"}]' # > /dev/null
      if [ "$AUPHONIC_IN" != "$AUPHONIC_OUT" ] ; then
        # if different from input destination, copy input files to output
        if [ "$TRACKS" -gt 1 ] ; then
          curl -H "Content-Type: application/json" -X POST \
           https://auphonic.com/api/production/$UUID/output_files.json \
           -u $AUPHONIC_USER:$AUPHONIC_PASS \
           -d '[{"format":"tracks"}]' > /dev/null
        else
          curl -H "Content-Type: application/json" -X POST \
           https://auphonic.com/api/production/$UUID/output_files.json \
           -u $AUPHONIC_USER:$AUPHONIC_PASS \
           -d '[{"format":"input"}]' # > /dev/null
        fi
      fi
    else 
      DOWNLOAD_FLAG="download files"
    fi
  fi  
    
  # start production
  JSON=$(curl -X POST https://auphonic.com/api/production/$UUID/start.json -u $AUPHONIC_USER:$AUPHONIC_PASS)
  auphonic_error_check
 
  # check once every 30 seconds, if production is done. Abort after checking set number of times
  TIMER=$(($TIMEOUT * 2))
  while [[ $JSON != *"\"status_string\": \"Done\""* ]] ; do
    sleep 30
    JSON=$(curl https://auphonic.com/api/production/$UUID.json -u $AUPHONIC_USER:$AUPHONIC_PASS)    
    auphonic_error_check
    if [ $TIMER -eq 0 ] ; then
      printf 'Auphonic transcription timed out\n\n'
      cleanup auphonic
      help_and_exit 1
    fi
    let "TIMER-=1"
  done

  # download the results from Auphonic
  if [ -n "$DOWNLOAD_FLAG" ] || [[ "$DESTINATION" == /** ]] ; then
    URLS=$(grep 'download_url' <<< "$JSON" | sed 's#^.*"download_url": "##g' | sed 's#",##g' | sed 's#"##g' )
    # turn this into proper array:
    IFS=$'\n' URLS=(${URLS})
    # download and move
    for url in "${URLS[@]}" ; do    
      DOWNLOADITEM="${url##*/}"
      cd "$OUTPUT_DIR" && { curl -O "$url" -u $AUPHONIC_USER:$AUPHONIC_PASS ; output move "$OUTPUT_DIR/$DOWNLOADITEM" ; cd - >/dev/null; } 
    done
  fi
  
  cleanup auphonic
fi
#done Auphonic transcription

cleanup all

# eof