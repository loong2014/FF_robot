# Sample Collection Guide

This guide describes how to collect audio samples for keyword spotting training.

## Goal

The model is a wake-word detector. It needs examples of:

- positive samples: utterances of the wake word
- negative samples: anything else the device may hear

## What to Collect

### Positive Samples

Record the wake word itself, for example:

- `Lumi`
- `Hey Robot`

Recommended coverage:

- multiple speakers
- different speaking speeds
- different loudness levels
- different accents if possible
- different recording environments

### Negative Samples

Collect audio that should not trigger wake-up:

- normal conversation
- background TV or radio
- office noise
- car noise
- silence
- near-miss phrases that sound similar to the wake word

Negative data matters at least as much as positive data. If negative coverage is weak, the model will over-trigger.

## Minimum Practical Amounts

Use these as working targets:

- prototype / pipeline validation:
  - 20 to 50 positive clips
  - 100 to 200 negative clips
- first usable model:
  - 100 to 200 positive clips
  - 500 to 1000 negative clips
- better first release:
  - 300+ positive clips
  - 2000+ negative clips

## Recording Rules

Keep each clip:

- short
- clean
- single-channel
- 16 kHz if possible

Recommended duration:

- positive clips: about 0.5 to 2 seconds
- negative clips: can be longer, but avoid huge files

Avoid:

- clipped audio
- heavily compressed audio
- multiple wake-word occurrences in the same short clip
- inconsistent sample rates

## Directory Layout

Use this structure:

```text
data/
  positive/
    Lumi/
      *.wav
    Hey Robot/
      *.wav
  negative/
    *.wav
```

You can also keep everything under `data/positive/` and label by file path or filename, but subdirectories are the cleanest option.

## Naming Suggestions

Positive examples:

- `data/positive/Lumi/lumi_0001.wav`
- `data/positive/Lumi/lumi_0002.wav`
- `data/positive/Hey Robot/hey_robot_0001.wav`

Negative examples:

- `data/negative/noise_0001.wav`
- `data/negative/conversation_0001.wav`
- `data/negative/office_0001.wav`

## Quality Checklist

Before keeping a clip, ask:

- Is the wake word clearly audible?
- Is there enough silence before and after the word?
- Is the file mono?
- Is it 16 kHz PCM WAV?
- Does it contain only one target phrase?

If the answer is no to any of these, re-record or exclude the clip.

