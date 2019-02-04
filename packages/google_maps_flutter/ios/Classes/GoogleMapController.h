// Copyright 2018 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import <Flutter/Flutter.h>
#import <GoogleMaps/GoogleMaps.h>
#import <UIKit/UIKit.h>
#import "GoogleMapMarkerController.h"
#import "GoogleMapPolylineController.h"

// Defines map UI options writable from Flutter.
@protocol FLTGoogleMapOptionsSink
- (void)setCameraTargetBounds:(GMSCoordinateBounds*)bounds;
- (void)setCompassEnabled:(BOOL)enabled;
- (void)setMapType:(GMSMapViewType)type;
- (void)setMapStyle:(NSString*)style;
- (void)setMinZoom:(float)minZoom maxZoom:(float)maxZoom;
- (void)setRotateGesturesEnabled:(BOOL)enabled;
- (void)setScrollGesturesEnabled:(BOOL)enabled;
- (void)setTiltGesturesEnabled:(BOOL)enabled;
- (void)setTrackCameraPosition:(BOOL)enabled;
- (void)setZoomGesturesEnabled:(BOOL)enabled;
- (void)setMyLocationEnabled:(BOOL)enabled;
@end

// Defines map overlay controllable from Flutter.
@interface FLTGoogleMapController
: NSObject <GMSMapViewDelegate, FLTGoogleMapOptionsSink, FlutterPlatformView>
- (instancetype)initWithFrame:(CGRect)frame
               viewIdentifier:(int64_t)viewId
                    arguments:(id _Nullable)args
                    registrar:(NSObject<FlutterPluginRegistrar>*)registrar;
- (void)showAtX:(CGFloat)x Y:(CGFloat)y;
- (void)hide;
- (void)animateWithCameraUpdate:(GMSCameraUpdate*)cameraUpdate;
- (void)moveWithCameraUpdate:(GMSCameraUpdate*)cameraUpdate;
- (GMSCameraPosition*)cameraPosition;
- (NSString*)addMarkerWithPosition:(CLLocationCoordinate2D)position;
- (FLTGoogleMapMarkerController*)markerWithId:(NSString*)markerId;
- (void)removeMarkerWithId:(NSString*)markerId;
- (NSString*)addPolylineWithPath:(GMSPath*)path;
- (FLTGoogleMapPolylineController*)polylineWithId:(NSString*)polylineId;
- (void)removePolylineWithId:(NSString*)polylineId;
@end

// Allows the engine to create new Google Map instances.
@interface FLTGoogleMapFactory : NSObject <FlutterPlatformViewFactory>
- (instancetype)initWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar;
@end
