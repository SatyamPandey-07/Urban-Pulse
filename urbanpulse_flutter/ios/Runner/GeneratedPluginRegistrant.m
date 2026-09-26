//
//  Generated file. Do not edit.
//

// clang-format off

#import "GeneratedPluginRegistrant.h"

#if __has_include(<app_links/AppLinksIosPlugin.h>)
#import <app_links/AppLinksIosPlugin.h>
#else
@import app_links;
#endif

#if __has_include(<geocoding_darwin/GeocodingDarwinPlugin.h>)
#import <geocoding_darwin/GeocodingDarwinPlugin.h>
#else
@import geocoding_darwin;
#endif

#if __has_include(<geolocator_apple/GeolocatorPlugin.h>)
#import <geolocator_apple/GeolocatorPlugin.h>
#else
@import geolocator_apple;
#endif

#if __has_include(<package_info_plus/FPPPackageInfoPlusPlugin.h>)
#import <package_info_plus/FPPPackageInfoPlusPlugin.h>
#else
@import package_info_plus;
#endif

#if __has_include(<printing/PrintingPlugin.h>)
#import <printing/PrintingPlugin.h>
#else
@import printing;
#endif

#if __has_include(<shared_preferences_foundation/SharedPreferencesPlugin.h>)
#import <shared_preferences_foundation/SharedPreferencesPlugin.h>
#else
@import shared_preferences_foundation;
#endif

#if __has_include(<speech_to_text/SpeechToTextPlugin.h>)
#import <speech_to_text/SpeechToTextPlugin.h>
#else
@import speech_to_text;
#endif

#if __has_include(<sqflite_darwin/SqflitePlugin.h>)
#import <sqflite_darwin/SqflitePlugin.h>
#else
@import sqflite_darwin;
#endif

#if __has_include(<url_launcher_ios/URLLauncherPlugin.h>)
#import <url_launcher_ios/URLLauncherPlugin.h>
#else
@import url_launcher_ios;
#endif

#if __has_include(<webview_flutter_wkwebview/WebViewFlutterPlugin.h>)
#import <webview_flutter_wkwebview/WebViewFlutterPlugin.h>
#else
@import webview_flutter_wkwebview;
#endif

@implementation GeneratedPluginRegistrant

+ (void)registerWithRegistry:(NSObject<FlutterPluginRegistry>*)registry {
  [AppLinksIosPlugin registerWithRegistrar:[registry registrarForPlugin:@"AppLinksIosPlugin"]];
  [GeocodingDarwinPlugin registerWithRegistrar:[registry registrarForPlugin:@"GeocodingDarwinPlugin"]];
  [GeolocatorPlugin registerWithRegistrar:[registry registrarForPlugin:@"GeolocatorPlugin"]];
  [FPPPackageInfoPlusPlugin registerWithRegistrar:[registry registrarForPlugin:@"FPPPackageInfoPlusPlugin"]];
  [PrintingPlugin registerWithRegistrar:[registry registrarForPlugin:@"PrintingPlugin"]];
  [SharedPreferencesPlugin registerWithRegistrar:[registry registrarForPlugin:@"SharedPreferencesPlugin"]];
  [SpeechToTextPlugin registerWithRegistrar:[registry registrarForPlugin:@"SpeechToTextPlugin"]];
  [SqflitePlugin registerWithRegistrar:[registry registrarForPlugin:@"SqflitePlugin"]];
  [URLLauncherPlugin registerWithRegistrar:[registry registrarForPlugin:@"URLLauncherPlugin"]];
  [WebViewFlutterPlugin registerWithRegistrar:[registry registrarForPlugin:@"WebViewFlutterPlugin"]];
}

@end
