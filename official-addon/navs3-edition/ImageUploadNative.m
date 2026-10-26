#import "ImageUploadTransport.h"
#import "ProtocolContext.h"
#import <objc/message.h>
TIOImageUploadTransport *TIOImageUploadOfficialTransport(NSURL *root,NSString *device){
 return [[TIOImageUploadTransport alloc]initWithRoot:root device:device currentDevice:^{return TIOProtocolDevice();} call:^BOOL(NSString *method,NSDictionary *args,void(^result)(id)){
  if(!NSThread.isMainThread||![method isEqual:@"rayneonet_sendFile"]||![TIOProtocolDevice() isEqual:device])return NO;
  id plugin=TIOProtocolPlugin();Class cls=NSClassFromString(@"FlutterMethodCall");
  SEL make=NSSelectorFromString(@"methodCallWithMethodName:arguments:"),handle=NSSelectorFromString(@"handleMethodCall:result:");
  if(!plugin||![cls respondsToSelector:make]||![plugin respondsToSelector:handle])return NO;
  @try{id call=((id(*)(id,SEL,id,id))objc_msgSend)(cls,make,method,args);
   ((void(*)(id,SEL,id,id))objc_msgSend)(plugin,handle,call,[result copy]);return YES;
  }@catch(NSException *e){return NO;}
 }];
}
