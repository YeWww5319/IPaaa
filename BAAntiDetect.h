//
//  BAAntiDetect.h — 防封 / 环境隐藏
//  思路：只隐藏越狱与注入痕迹，不碰游戏业务逻辑、不改内存数据、不发异常网络包。
//        客户端不改成绩 → 服务端风控看到的一切都正常，这是最稳的防封。
//

#ifndef BAANTIDETECT_H
#define BAANTIDETECT_H

#import <Foundation/Foundation.h>

@interface BAAntiDetect : NSObject
+ (void)install;
@end

#endif
