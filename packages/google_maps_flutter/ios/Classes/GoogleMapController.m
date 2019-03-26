// Copyright 2018 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "GoogleMapController.h"
#import "GoogleMapPolylineController.h"
#import "JsonConversions.h"

#pragma mark - Conversion of JSON-like values sent via platform channels. Forward declarations.

static NSDictionary* PositionToJson(GMSCameraPosition* position);
static GMSCameraPosition* ToOptionalCameraPosition(NSDictionary* json);
static GMSCoordinateBounds* ToOptionalBounds(NSArray* json);
static GMSCameraUpdate* ToCameraUpdate(NSArray* data);
static GMSPath* toPath(id json);
static void interpretMarkerOptions(id json, id<FLTGoogleMapMarkerOptionsSink> sink,
                                   NSObject<FlutterPluginRegistrar>* registrar);
static void interpretPolylineOptions(id json, id<FLTGoogleMapPolylineOptionsSink> sink,
                                     NSObject<FlutterPluginRegistrar>* registrar);
static void InterpretMapOptions(NSDictionary* data, id<FLTGoogleMapOptionsSink> sink);
static double ToDouble(NSNumber* data) { return [FLTGoogleMapJsonConversions toDouble:data]; }

@implementation FLTGoogleMapFactory {
  NSObject<FlutterPluginRegistrar>* _registrar;
}

- (instancetype)initWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  self = [super init];
  if (self) {
    _registrar = registrar;
  }
  return self;
}

- (NSObject<FlutterMessageCodec>*)createArgsCodec {
  return [FlutterStandardMessageCodec sharedInstance];
}

- (NSObject<FlutterPlatformView>*)createWithFrame:(CGRect)frame
                                   viewIdentifier:(int64_t)viewId
                                        arguments:(id _Nullable)args {
  return [[FLTGoogleMapController alloc] initWithFrame:frame
                                        viewIdentifier:viewId
                                             arguments:args
                                             registrar:_registrar];
}
@end

@implementation FLTGoogleMapController {
  GMSMapView* _mapView;
  int64_t _viewId;
  FlutterMethodChannel* _channel;
  BOOL _trackCameraPosition;
  NSObject<FlutterPluginRegistrar>* _registrar;
  // Used for the temporary workaround for a bug that the camera is not properly positioned at
  // initialization. https://github.com/flutter/flutter/issues/24806
  // TODO(cyanglaz): Remove this temporary fix once the Maps SDK issue is resolved.
  // https://github.com/flutter/flutter/issues/27550
  BOOL _cameraDidInitialSetup;
  FLTMarkersController* _markersController;
    NSMutableDictionary* _polylines;
}

- (instancetype)initWithFrame:(CGRect)frame
               viewIdentifier:(int64_t)viewId
                    arguments:(id _Nullable)args
                    registrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  if ([super init]) {
    _viewId = viewId;

    GMSCameraPosition* camera = ToOptionalCameraPosition(args[@"initialCameraPosition"]);
    _mapView = [GMSMapView mapWithFrame:frame camera:camera];
      _mapView.settings.myLocationButton = false;
    _trackCameraPosition = NO;
    InterpretMapOptions(args[@"options"], self);
    NSString* channelName =
        [NSString stringWithFormat:@"plugins.flutter.io/google_maps_%lld", viewId];
    _channel = [FlutterMethodChannel methodChannelWithName:channelName
                                           binaryMessenger:registrar.messenger];
    __weak __typeof__(self) weakSelf = self;
    [_channel setMethodCallHandler:^(FlutterMethodCall* call, FlutterResult result) {
      if (weakSelf) {
        [weakSelf onMethodCall:call result:result];
      }
    }];
    _mapView.delegate = weakSelf;
    _registrar = registrar;
    _cameraDidInitialSetup = NO;
    _markersController = [[FLTMarkersController alloc] init:_channel
                                                    mapView:_mapView
                                                  registrar:registrar];
    id markersToAdd = args[@"markersToAdd"];
    if ([markersToAdd isKindOfClass:[NSArray class]]) {
      [_markersController addMarkers:markersToAdd];
    }
      _polylines = [NSMutableDictionary dictionaryWithCapacity:1];

  }
  return self;
}

- (UIView*)view {
  return _mapView;
}

- (void)onMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
  if ([call.method isEqualToString:@"map#show"]) {
    [self showAtX:ToDouble(call.arguments[@"x"]) Y:ToDouble(call.arguments[@"y"])];
    result(nil);
  } else if ([call.method isEqualToString:@"map#hide"]) {
    [self hide];
    result(nil);
  } else if ([call.method isEqualToString:@"camera#animate"]) {
      [self animateWithCameraUpdate:ToCameraUpdate(call.arguments[@"cameraUpdate"]) :ToDouble(call.arguments[@"duration"])];
    result(nil);
  } else if ([call.method isEqualToString:@"camera#move"]) {
    [self moveWithCameraUpdate:ToCameraUpdate(call.arguments[@"cameraUpdate"])];
    result(nil);
  } else if ([call.method isEqualToString:@"map#update"]) {
    InterpretMapOptions(call.arguments[@"options"], self);
    result(PositionToJson([self cameraPosition]));
  } else if ([call.method isEqualToString:@"map#waitForMap"]) {
    result(nil);
  } else if ([call.method isEqualToString:@"markers#update"]) {
    id markersToAdd = call.arguments[@"markersToAdd"];
    if ([markersToAdd isKindOfClass:[NSArray class]]) {
      [_markersController addMarkers:markersToAdd];
    }
    id markersToChange = call.arguments[@"markersToChange"];
    if ([markersToChange isKindOfClass:[NSArray class]]) {
      [_markersController changeMarkers:markersToChange];
    }
    id markerIdsToRemove = call.arguments[@"markerIdsToRemove"];
    if ([markerIdsToRemove isKindOfClass:[NSArray class]]) {
      [_markersController removeMarkerIds:markerIdsToRemove];
    }
    result(nil);
  } else if ([call.method isEqualToString:@"map#isCoordinateOnScreen"]) {
      NSNumber *onscreen = [NSNumber numberWithBool:[self isCoordinateOnScreen:ToDouble(call.arguments[@"lat"]) Y:ToDouble(call.arguments[@"lng"])]];
      result(onscreen);
  } else if ([call.method isEqualToString:@"map#setStyle"]) {
      [self setMapStyle:call.arguments[@"style"]];
      result(nil);
  } else if ([call.method isEqualToString:@"polyline#add"]) {
      NSDictionary* options = call.arguments[@"options"];
      NSString* polylineId = [self addPolylineWithPath:toPath(options[@"points"])];
      interpretPolylineOptions(options, [self polylineWithId:polylineId], _registrar);
      result(polylineId);
  } else if ([call.method isEqualToString:@"polyline#update"]) {
      interpretPolylineOptions(call.arguments[@"options"],
                               [self polylineWithId:call.arguments[@"polyline"]], _registrar);
      result(nil);
  } else if ([call.method isEqualToString:@"polyline#remove"]) {
      [self removePolylineWithId:call.arguments[@"polyline"]];
      result(nil);
  } else if ([call.method isEqualToString:@"map#getVisibleRegion"]) {
      NSDictionary *data = [self getVisibleRegion];
      result(data);
  } else {
    result(FlutterMethodNotImplemented);
  }
}

- (NSDictionary*)getVisibleRegion {
    GMSProjection *projection = _mapView.projection;
    GMSVisibleRegion region = projection.visibleRegion;
    
    NSDictionary *data = @{
                           @"farLeft": @{
                                   @"latitude": @(region.farLeft.latitude),
                                   @"longitude": @(region.farLeft.longitude)
                                   },
                           @"farRight": @{
                                   @"latitude": @(region.farRight.latitude),
                                   @"longitude": @(region.farRight.longitude)
                                   },
                           @"nearLeft": @{
                                   @"latitude": @(region.nearLeft.latitude),
                                   @"longitude": @(region.nearLeft.longitude)
                                   },
                           @"nearRight": @{
                                   @"latitude": @(region.nearRight.latitude),
                                   @"longitude": @(region.nearRight.longitude)
                                   },
                           };
    
    return data;
}

- (NSString*)addPolylineWithPath:(GMSPath*)path {
    FLTGoogleMapPolylineController* polylineController =
    [[FLTGoogleMapPolylineController alloc] initWithPath:path mapView:_mapView];
    _polylines[polylineController.polylineId] = polylineController;
    return polylineController.polylineId;
}

- (FLTGoogleMapPolylineController*)polylineWithId:(NSString*)polylineId {
    return _polylines[polylineId];
}

- (void)removePolylineWithId:(NSString*)polylineId {
    FLTGoogleMapPolylineController* polylineController = _polylines[polylineId];
    if (polylineController) {
        [polylineController setVisible:NO];
        [_polylines removeObjectForKey:polylineId];
    }
}

- (void)setMapStyle:(NSString*)style {
    NSError *error;
    GMSMapStyle *mapStyle = [GMSMapStyle styleWithJSONString:style error:&error];
    _mapView.mapStyle = mapStyle;
}

- (BOOL)isCoordinateOnScreen:(double)x Y:(double)y {
    CLLocationCoordinate2D position = CLLocationCoordinate2DMake(x, y);
    return [_mapView.projection containsCoordinate:position];
}

- (void)showAtX:(CGFloat)x Y:(CGFloat)y {
  _mapView.frame =
      CGRectMake(x, y, CGRectGetWidth(_mapView.frame), CGRectGetHeight(_mapView.frame));
  _mapView.hidden = NO;
}

- (void)hide {
  _mapView.hidden = YES;
}

- (void)animateWithCameraUpdate:(GMSCameraUpdate*)cameraUpdate :(float)duration  {
    if (duration == 0.0f) {
        [_mapView animateWithCameraUpdate:cameraUpdate];
    }
    else {
        float durationSeconds = duration / 1000.0f;
        [CATransaction begin];
        [CATransaction setValue:[NSNumber numberWithFloat: durationSeconds] forKey:kCATransactionAnimationDuration];
        [CATransaction setAnimationTimingFunction: [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut]];
        [_mapView animateWithCameraUpdate:cameraUpdate];
        [CATransaction commit];
    }
}

- (void)moveWithCameraUpdate:(GMSCameraUpdate*)cameraUpdate {
  [_mapView moveCamera:cameraUpdate];
}

- (GMSCameraPosition*)cameraPosition {
  if (_trackCameraPosition) {
    return _mapView.camera;
  } else {
    return nil;
  }
}

static GMSPath* toPath(id json) {
    NSArray* data = json;
    GMSMutablePath* path = [GMSMutablePath path];
    for (id object in data) {
        NSArray* d = object;
        [path addCoordinate:CLLocationCoordinate2DMake(ToDouble(d[0]), ToDouble(d[1]))];
    }
    return path;
}

#pragma mark - FLTGoogleMapOptionsSink methods

- (void)setCamera:(GMSCameraPosition*)camera {
  _mapView.camera = camera;
}

- (void)setCameraTargetBounds:(GMSCoordinateBounds*)bounds {
  _mapView.cameraTargetBounds = bounds;
}

- (void)setCompassEnabled:(BOOL)enabled {
  _mapView.settings.compassButton = enabled;
}

- (void)setMapType:(GMSMapViewType)mapType {
  _mapView.mapType = mapType;
}

- (void)setMinZoom:(float)minZoom maxZoom:(float)maxZoom {
  [_mapView setMinZoom:minZoom maxZoom:maxZoom];
}

- (void)setRotateGesturesEnabled:(BOOL)enabled {
  _mapView.settings.rotateGestures = enabled;
}

- (void)setScrollGesturesEnabled:(BOOL)enabled {
  _mapView.settings.scrollGestures = enabled;
}

- (void)setTiltGesturesEnabled:(BOOL)enabled {
  _mapView.settings.tiltGestures = enabled;
}

- (void)setTrackCameraPosition:(BOOL)enabled {
  _trackCameraPosition = enabled;
}

- (void)setZoomGesturesEnabled:(BOOL)enabled {
  _mapView.settings.zoomGestures = enabled;
}

- (void)setMyLocationEnabled:(BOOL)enabled {
  _mapView.myLocationEnabled = enabled;
  _mapView.settings.myLocationButton = false;
}

#pragma mark - GMSMapViewDelegate methods

- (void)mapView:(GMSMapView*)mapView willMove:(BOOL)gesture {
  [_channel invokeMethod:@"camera#onMoveStarted" arguments:@{@"isGesture" : @(gesture)}];
}

- (void)mapView:(GMSMapView*)mapView didChangeCameraPosition:(GMSCameraPosition*)position {
  if (!_cameraDidInitialSetup) {
    // We suspected a bug in the iOS Google Maps SDK caused the camera is not properly positioned at
    // initialization. https://github.com/flutter/flutter/issues/24806
    // This temporary workaround fix is provided while the actual fix in the Google Maps SDK is
    // still being investigated.
    // TODO(cyanglaz): Remove this temporary fix once the Maps SDK issue is resolved.
    // https://github.com/flutter/flutter/issues/27550
    _cameraDidInitialSetup = YES;
    [mapView moveCamera:[GMSCameraUpdate setCamera:_mapView.camera]];
  }
  if (_trackCameraPosition) {
    [_channel invokeMethod:@"camera#onMove" arguments:@{@"position" : PositionToJson(position)}];
  }
}

- (void)mapView:(GMSMapView*)mapView idleAtCameraPosition:(GMSCameraPosition*)position {
  [_channel invokeMethod:@"camera#onIdle" arguments:@{}];
}

- (BOOL)mapView:(GMSMapView*)mapView didTapMarker:(GMSMarker*)marker {
  NSString* markerId = marker.userData[0];
  return [_markersController onMarkerTap:markerId];
}

- (void)mapView:(GMSMapView*)mapView didTapInfoWindowOfMarker:(GMSMarker*)marker {
  NSString* markerId = marker.userData[0];
  [_markersController onInfoWindowTap:markerId];
}

@end

#pragma mark - Implementations of JSON conversion functions.

static NSArray* LocationToJson(CLLocationCoordinate2D position) {
  return @[ @(position.latitude), @(position.longitude) ];
}

static NSDictionary* PositionToJson(GMSCameraPosition* position) {
  if (!position) {
    return nil;
  }
  return @{
    @"target" : LocationToJson([position target]),
    @"zoom" : @([position zoom]),
    @"bearing" : @([position bearing]),
    @"tilt" : @([position viewingAngle]),
  };
}

static float ToFloat(NSNumber* data) { return [FLTGoogleMapJsonConversions toFloat:data]; }

static CLLocationCoordinate2D ToLocation(NSArray* data) {
  return [FLTGoogleMapJsonConversions toLocation:data];
}

static int ToInt(NSNumber* data) { return [FLTGoogleMapJsonConversions toInt:data]; }

static BOOL ToBool(NSNumber* data) { return [FLTGoogleMapJsonConversions toBool:data]; }

static CGPoint ToPoint(NSArray* data) { return [FLTGoogleMapJsonConversions toPoint:data]; }

static GMSCameraPosition* ToCameraPosition(NSDictionary* data) {
  return [GMSCameraPosition cameraWithTarget:ToLocation(data[@"target"])
                                        zoom:ToFloat(data[@"zoom"])
                                     bearing:ToDouble(data[@"bearing"])
                                viewingAngle:ToDouble(data[@"tilt"])];
}

static GMSCameraPosition* ToOptionalCameraPosition(NSDictionary* json) {
  return json ? ToCameraPosition(json) : nil;
}

static GMSCoordinateBounds* ToBounds(NSArray* data) {
  return [[GMSCoordinateBounds alloc] initWithCoordinate:ToLocation(data[0])
                                              coordinate:ToLocation(data[1])];
}

static GMSCoordinateBounds* ToOptionalBounds(NSArray* data) {
  return (data[0] == [NSNull null]) ? nil : ToBounds(data[0]);
}

static GMSMapViewType ToMapViewType(NSNumber* json) {
  int value = ToInt(json);
  return (GMSMapViewType)(value == 0 ? 5 : value);
}

static GMSCameraUpdate* ToCameraUpdate(NSArray* data) {
  NSString* update = data[0];
  if ([update isEqualToString:@"newCameraPosition"]) {
    return [GMSCameraUpdate setCamera:ToCameraPosition(data[1])];
  } else if ([update isEqualToString:@"newLatLng"]) {
    return [GMSCameraUpdate setTarget:ToLocation(data[1])];
  } else if ([update isEqualToString:@"newLatLngBounds"]) {
    return [GMSCameraUpdate fitBounds:ToBounds(data[1]) withPadding:ToDouble(data[2])];
  } else if ([update isEqualToString:@"newLatLngZoom"]) {
    return [GMSCameraUpdate setTarget:ToLocation(data[1]) zoom:ToFloat(data[2])];
  } else if ([update isEqualToString:@"scrollBy"]) {
    return [GMSCameraUpdate scrollByX:ToDouble(data[1]) Y:ToDouble(data[2])];
  } else if ([update isEqualToString:@"zoomBy"]) {
    if (data.count == 2) {
      return [GMSCameraUpdate zoomBy:ToFloat(data[1])];
    } else {
      return [GMSCameraUpdate zoomBy:ToFloat(data[1]) atPoint:ToPoint(data[2])];
    }
  } else if ([update isEqualToString:@"zoomIn"]) {
    return [GMSCameraUpdate zoomIn];
  } else if ([update isEqualToString:@"zoomOut"]) {
    return [GMSCameraUpdate zoomOut];
  } else if ([update isEqualToString:@"zoomTo"]) {
    return [GMSCameraUpdate zoomTo:ToFloat(data[1])];
  }
  return nil;
}

static void InterpretMapOptions(NSDictionary* data, id<FLTGoogleMapOptionsSink> sink) {
  NSArray* cameraTargetBounds = data[@"cameraTargetBounds"];
  if (cameraTargetBounds) {
    [sink setCameraTargetBounds:ToOptionalBounds(cameraTargetBounds)];
  }
  NSNumber* compassEnabled = data[@"compassEnabled"];
  if (compassEnabled) {
    [sink setCompassEnabled:ToBool(compassEnabled)];
  }
  NSNumber* mapType = data[@"mapType"];
  if (mapType) {
    [sink setMapType:ToMapViewType(mapType)];
  }
  NSArray* zoomData = data[@"minMaxZoomPreference"];
  if (zoomData) {
    float minZoom = (zoomData[0] == [NSNull null]) ? kGMSMinZoomLevel : ToFloat(zoomData[0]);
    float maxZoom = (zoomData[1] == [NSNull null]) ? kGMSMaxZoomLevel : ToFloat(zoomData[1]);
    [sink setMinZoom:minZoom maxZoom:maxZoom];
  }
  NSNumber* rotateGesturesEnabled = data[@"rotateGesturesEnabled"];
  if (rotateGesturesEnabled) {
    [sink setRotateGesturesEnabled:ToBool(rotateGesturesEnabled)];
  }
  NSNumber* scrollGesturesEnabled = data[@"scrollGesturesEnabled"];
  if (scrollGesturesEnabled) {
    [sink setScrollGesturesEnabled:ToBool(scrollGesturesEnabled)];
  }
  NSNumber* tiltGesturesEnabled = data[@"tiltGesturesEnabled"];
  if (tiltGesturesEnabled) {
    [sink setTiltGesturesEnabled:ToBool(tiltGesturesEnabled)];
  }
  NSNumber* trackCameraPosition = data[@"trackCameraPosition"];
  if (trackCameraPosition) {
    [sink setTrackCameraPosition:ToBool(trackCameraPosition)];
  }
  NSNumber* zoomGesturesEnabled = data[@"zoomGesturesEnabled"];
  if (zoomGesturesEnabled) {
    [sink setZoomGesturesEnabled:ToBool(zoomGesturesEnabled)];
  }
  NSNumber* myLocationEnabled = data[@"myLocationEnabled"];
  if (myLocationEnabled) {
    [sink setMyLocationEnabled:ToBool(myLocationEnabled)];
  }
}

static void interpretPolylineOptions(id json, id<FLTGoogleMapPolylineOptionsSink> sink,
                                     NSObject<FlutterPluginRegistrar>* registrar) {
    NSDictionary* data = json;
    
    id points = data[@"points"];
    if (points) {
        [sink setPoints:toPath(points)];
    }
    id clickable = data[@"clickable"];
    if (clickable) {
        [sink setClickable:ToBool(clickable)];
    }
    //id color = data[@"color"];
    /*if (color) {
        [sink setColor:UIColorFromRGB(ToInt(color))];
    }*/
    id geodesic = data[@"geodesic"];
    if (geodesic) {
        [sink setGeodesic:ToBool(geodesic)];
    }
    id width = data[@"width"];
    if (width) {
        [sink setWidth:(CGFloat)ToFloat(width)];
    }
    id visible = data[@"visible"];
    if (visible) {
        [sink setVisible:ToBool(visible)];
    }
    id zIndex = data[@"zIndex"];
    if (zIndex) {
        [sink setZIndex:ToInt(zIndex)];
    }
}
