# real-voice
Scripts for working with a real voice in Synthesizer V

## What is this good for
Usually "tuning" a voice in a vocal synthesizer means drawing some pitch curve over MIDI notes. The timing of the notes is seldom changed.

I wanted to do a different thing - get the pitch curve from a real singer and change the timing to fit it. The timing means the lenghts of phonemes and pauses.
This way it also should sound better and it does - after all, it is partly from a real person. I call it "Voice Copy". It is inaccurate, copied are only some prosodic features.

The scripts in this repository are designed to make the process easier.

## Installation
If you want to use these scripts, you have to have Dreamtonics [Synthesizer V Studio Pro](https://dreamtonics.com/en/synthesizerv/), which enables scripting.
Everything is tested only on Windows, but it should work on other platforms where Studio Pro is working.

- Download this [zip archive](https://github.com/hataori-p/real-voice/archive/refs/heads/main.zip),
- unzip it,
- and copy/move whole folder real-voice-main to SynthV's scripts folder at path C:\\Users\\<user_name>\\Documents\\Dreamtonics\\Synthesizer V Studio\\scripts\\
- You can open the scripts folder from MainMenu / Scripts / Open Scripts folder command and rename real-voice-main to whatever you want, eg. realVoice

After starting SynthV Studio (or rescanning scripts) you should have these scripts in the Scripts Menu:
- RV Load Envelope
- RV Load Pitch
- RV Quantize Pitch
- RV Split Note

I recommend to set up a keyboard shortcuts for RV Load Pitch (I use alt-X) and for RV Split Note (alt-C)

## Other software needed
You will also need [Praat](https://www.fon.hum.uva.nl/praat/) phonetic program installed and be able to run it.
It is available for many platforms.

## Demo videos
For the instructions how to use these scripts refer to my demonstration videos on Youtube:
