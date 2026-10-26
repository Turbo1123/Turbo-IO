#import <UIKit/UIKit.h>
// Fixed-size pixels only; no image files or coordinates written to disk.
NSData *TDPHUDImagePixels(UIImage *image,BOOL cross);
NSDictionary *TDPHUDDecorate(NSDictionary *frame,NSData *callbackIcon,NSInteger callbackType,NSData *cross);
UIImage *TDPHUDPreview(NSDictionary *frame);
