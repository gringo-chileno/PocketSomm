# WineMenuScanner

An iOS app that lets you rate wines. Then you can scan the wine menu in a restaurant and it will make recommendations based on your preferences and community ratings.

I called it Pocket Somm, but that name is already being used by other apps. So I'd have to change it if I ever pick this project up again.

## Features

- **Scan wine menus** - Use your camera to scan restaurant wine lists
- **Wine database** - Look up wines with ratings and details
- **Personal ratings** - Track and rate wines you've tried
- **Scan history** - Review past scans
- **Vivino import** - Import your existing Vivino ratings

## Requirements

- iOS 17.0+
- Xcode 15.0+

## Getting Started

1. Clone the repo
   ```
   git clone https://github.com/gringo-chileno/WineMenuScanner.git
   ```
2. Open `WineMenuScanner.xcodeproj` in Xcode
3. Build and run on a device (camera required for scanning)

## Tech Stack

- SwiftUI
- SwiftData
- Vision framework (for text recognition)
