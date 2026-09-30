# Third-party notices

MioAmp uses [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) 0.9.19 for in-process ZIP archive handling. ZIPFoundation is Copyright © 2017–2024 Thomas Zoechling and is distributed under the MIT License. Its full license is available in the dependency source checkout and upstream repository.

MioAmp vendors [dr_flac](https://github.com/mackron/dr_libs) 0.13.3 from tag `flac-0.13.3` (commit `69d777c482775858e8ea8a7b047c9bcd451febc8`) as its bounded software FLAC decoder. dr_flac is Copyright 2023 David Reid and is used under the MIT No Attribution license. The complete license text is retained at the end of `Packages/MioAmpKit/Sources/CAudioDecoders/dr_flac.h`.

MioAmp vendors [dr_mp3](https://github.com/mackron/dr_libs) 0.7.3 from tag `mp3-0.7.3` (commit `5690d4671d7ad07ae6021756d7222eb159745f06`) as its bounded software MP3 decoder. dr_mp3 is Copyright 2023 David Reid and is used under the MIT No Attribution license. The complete license text is retained at the end of `Packages/MioAmpKit/Sources/CAudioDecoders/dr_mp3.h`.

All bundled MioAmp skin artwork and generated audio fixtures in this repository are original or generated for this project. Other runtime codec support uses Apple system frameworks; no FFmpeg binary is shipped in the app.
