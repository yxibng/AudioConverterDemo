# AudioConverterDemo
A Demo shows how to use iOS AudioConverterRef to resample PCM sampleRate.

1. how to read audio pcm from  [CMSampleBuffer](https://developer.apple.com/documentation/coremedia/cmsamplebuffer?language=objc)
2. how to use [AudioConverterFillComplexBuffer](https://developer.apple.com/documentation/audiotoolbox/1503098-audioconverterfillcomplexbuffer?language=objc)
3. how to use [AudioConverterComplexInputDataProc](https://developer.apple.com/documentation/audiotoolbox/audioconvertercomplexinputdataproc?language=objc)

Will write pcm to file to check if resample success or not. Use ffplay to play pcm:

```
# ffplay -ar <SampleRate> -ac 1 -f s16le -i <file.pcm>

# play file named xx.pcm, samplerate = 16000, fmt = s16le
ffplay -ar 16000 -ac 1 -f s16le -i xx.pcm
```
