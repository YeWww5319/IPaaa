//
//  BAOverlay.h — 屏幕上那层瞄准线（纯视觉，不碰游戏数据）
//

#ifndef BAOVERLAY_H
#define BAOVERLAY_H

#import <Foundation/Foundation.h>

@interface BAOverlay : NSObject
+ (instancetype)shared;
- (void)attach;
- (void)startCalibration;
@end

#endif
