#include "Tweak.h"

/**
 * Load Preferences
 */
BOOL noads;
BOOL unlimitedDownload;
BOOL downloadWithoutWatermark;
BOOL autoPlayNextVideo;
BOOL changeRegion;
NSDictionary *region;

static void reloadPrefs() {
  NSDictionary *settings = [[NSMutableDictionary alloc] initWithContentsOfFile:@PLIST_PATH] ?: [@{} mutableCopy];

  noads = [[settings objectForKey:@"noads"] ?: @(YES) boolValue];
  unlimitedDownload = [[settings objectForKey:@"unlimitedDownload"] ?: @(YES) boolValue];
  downloadWithoutWatermark = [[settings objectForKey:@"downloadWithoutWatermark"] ?: @(YES) boolValue];
  autoPlayNextVideo = [[settings objectForKey:@"autoPlayNextVideo"] ?: @(NO) boolValue];
  changeRegion = [[settings objectForKey:@"changeRegion"] ?: @(NO) boolValue];
  region = [settings objectForKey:@"region"] ?: [@{} mutableCopy];
}

static void showAlertMessage(NSString *title, NSString *message) {
  __block UIWindow* topWindow;
  topWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
  topWindow.rootViewController = [UIViewController new];
  topWindow.windowLevel = UIWindowLevelAlert + 1;
  UIAlertController* alert = [UIAlertController alertControllerWithTitle:title?:@"Alert" message:message preferredStyle:UIAlertControllerStyleAlert];
  [alert addAction:[UIAlertAction actionWithTitle:@"Ok" style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
    topWindow.hidden = YES;
    topWindow = nil;
  }]];

  [topWindow makeKeyAndVisible];
  [topWindow.rootViewController presentViewController:alert animated:YES completion:nil];
}

%group CoreLogic
  %hook AWEAwemeModel
    - (id)initWithDictionary:(id)arg1 error:(id *)arg2 {
      id orig = %orig;
      return noads && self.isAds ? nil : orig;
    }

    - (id)init {
      id orig = %orig;
      return noads && self.isAds ? nil : orig;
    }

    - (BOOL)preventDownload {
      return unlimitedDownload ? FALSE : %orig;
    }

    - (BOOL)disableDownload {
      return unlimitedDownload ? FALSE : %orig;
    }
  %end

  %hook AWEAwemePlayDislikeViewController
    - (BOOL)shouldShowDownload:(id)arg1 {
      return unlimitedDownload ? TRUE : %orig;
    }

    - (AWEAwemeDislikeNewReasonTableViewCell *)tableView:(id)arg1 cellForRowAtIndexPath:(NSIndexPath *)indexPath {
      AWEAwemeDislikeNewReasonTableViewCell *orig = %orig;
      if (downloadWithoutWatermark && orig.model.dislikeType == 1) {
        orig.titleLabel.text = [NSString stringWithFormat:@"%@%@", orig.titleLabel.text, @" - No Watermark"];
      }
      return orig;
    }

    - (void)tableView:(id)arg1 didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
      AWEAwemeDislikeNewReasonTableViewCell *cell = [self tableView:arg1 cellForRowAtIndexPath:indexPath];
      if (downloadWithoutWatermark && cell.model.dislikeType == 1) {
        [self didSelectDownloadCell];
        [self dismissActionsWithExecutingBlock];
        return;
      }
      %orig;
    }

    %new 
    - (void)didSelectDownloadCell {
      PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatus];
      switch(status) {
        case PHAuthorizationStatusNotDetermined:
          [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus authorizationStatus) {
            if(authorizationStatus == PHAuthorizationStatusAuthorized) {
              [self saveVideoToPhotoLibrary];
            }
          }];
          break;
        case PHAuthorizationStatusAuthorized:
          [self saveVideoToPhotoLibrary];
          break;
        case PHAuthorizationStatusDenied:
          UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Permission Required" message:@"TikTok needs permission to Photos" preferredStyle:UIAlertControllerStyleAlert];
          [alert addAction:[UIAlertAction actionWithTitle:@"Close" style:UIAlertActionStyleDefault handler:nil]];
          [alert addAction:[UIAlertAction actionWithTitle:@"Go To Settings" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
            [[UIApplication sharedApplication] openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString] options:@{} completionHandler:nil];
          }]];
          [self presentViewController:alert animated:YES completion:nil];
          break;
      }
    }

    %new
    - (void)saveVideoToPhotoLibrary {
      NSURL* videoUrl = [NSURL URLWithString:self.model.video.playURL.originURLList.firstObject];
      NSURLSessionDownloadTask* downloadTask = [[NSURLSession sharedSession] downloadTaskWithURL:videoUrl completionHandler:^(NSURL* location, NSURLResponse* response, NSError* error) {
        if (error) {
          dispatch_async(dispatch_get_main_queue(), ^{
            showAlertMessage(@"Download Error", [error localizedDescription]);
          });
        }
        NSString* fileName = [[videoUrl lastPathComponent] stringByAppendingPathExtension:@"mp4"];
        [location setResourceValue:fileName forKey:NSURLNameKey error:nil];
        location = [[location URLByDeletingLastPathComponent] URLByAppendingPathComponent:fileName];
        [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
                                                [PHAssetChangeRequest creationRequestForAssetFromVideoAtFileURL:location];
                                              } 
                                              completionHandler:^(BOOL success, NSError* error) {
                                                [[NSFileManager defaultManager] removeItemAtURL:location error:nil];
                                                if(success) {
                                                  dispatch_async(dispatch_get_main_queue(), ^{
                                                    showAlertMessage(nil, @"Download Success");
                                                  });
                                                } else {
                                                  dispatch_async(dispatch_get_main_queue(), ^{
                                                    showAlertMessage(@"Download Error", [error localizedDescription]);
                                                  });
                                                }
                                              }];
      }];
      [downloadTask resume];
    }
  %end

  // Thanks chenxk-j for this
  // https://github.com/chenxk-j/hookTikTok/blob/master/hooktiktok/hooktiktok.xm#L23
  %hook CTCarrier
    - (NSString *)mobileCountryCode {
      return (changeRegion && region[@"mcc"] != nil) ? region[@"mcc"] : %orig;
    }

    - (NSString *)isoCountryCode {
      return (changeRegion && region[@"code"] != nil) ? region[@"code"] : %orig;
    }

    - (NSString *)mobileNetworkCode {
      return (changeRegion && region[@"mnc"] != nil) ? region[@"mnc"] : %orig;
    }
  %end

  %hook AWEFeedGuideManager
    - (BOOL)enableAutoplay {
      return autoPlayNextVideo;
    }
  %end
%end


/**
 * Constructor
 */
%ctor {
  CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback) reloadPrefs, CFSTR(PREF_CHANGED_NOTIF), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
  reloadPrefs();

  %init(CoreLogic);
}

