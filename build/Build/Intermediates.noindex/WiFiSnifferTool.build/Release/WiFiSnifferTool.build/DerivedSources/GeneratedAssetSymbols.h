#import <Foundation/Foundation.h>

#if __has_attribute(swift_private)
#define AC_SWIFT_PRIVATE __attribute__((swift_private))
#else
#define AC_SWIFT_PRIVATE
#endif

/// The "WiFiSnifferToolAppIcon" asset catalog image resource.
static NSString * const ACImageNameWiFiSnifferToolAppIcon AC_SWIFT_PRIVATE = @"WiFiSnifferToolAppIcon";

/// The "wifi-sniffer" asset catalog image resource.
static NSString * const ACImageNameWifiSniffer AC_SWIFT_PRIVATE = @"wifi-sniffer";

/// The "wifi-sniffer-active" asset catalog image resource.
static NSString * const ACImageNameWifiSnifferActive AC_SWIFT_PRIVATE = @"wifi-sniffer-active";

#undef AC_SWIFT_PRIVATE
