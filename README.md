# safe-multisig-ios
Gnosis Safe Multisig iOS app.

[![codecov](https://codecov.io/gh/gnosis/safe-ios/branch/main/graph/badge.svg)](https://codecov.io/gh/gnosis/safe-ios)

# Coding Style
As of 18.03.2021, this project adopted the [Google's Swift Style Guide](https://google.github.io/swift/) as well as [Apple's Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/). 

Inconsistencies and differences between the project's source code and the aforementioned guidelines shall be corrected as a by-product of the normal work on feature development and bug fixes.

# Configuration

Export your Infura project key as an `INFURA_KEY` environment variable:

    $> export INFURA_KEY="..."


*Optional*. If you use the encrypted `Firebase.dat` configuration, provide the encryption key as 
environment variable.

    $> export ENCRYPTION_KEY="..."

The app will work without it, so that step can be skipped.

Then, run the configure script to install the Config.xcconfig

    $> bin/configure.sh

Now you are ready to build the project.

