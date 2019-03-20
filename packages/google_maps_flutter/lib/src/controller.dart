// Copyright 2018 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

part of google_maps_flutter;

/// Controller for a single GoogleMap instance running on the host platform.
class GoogleMapController {
  GoogleMapController._(
    MethodChannel channel,
    CameraPosition initialCameraPosition,
    this._googleMapState,
  )   : assert(channel != null),
        _channel = channel {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  static Future<GoogleMapController> init(
    int id,
    CameraPosition initialCameraPosition,
    _GoogleMapState googleMapState,
  ) async {
    assert(id != null);
    final MethodChannel channel =
        MethodChannel('plugins.flutter.io/google_maps_$id');
    // TODO(amirh): remove this on when the invokeMethod update makes it to stable Flutter.
    // https://github.com/flutter/flutter/issues/26431
    // ignore: strong_mode_implicit_dynamic_method
    await channel.invokeMethod('map#waitForMap');
    return GoogleMapController._(
      channel,
      initialCameraPosition,
      googleMapState,
    );
  }

  final MethodChannel _channel;

  /// Callbacks to receive tap events for markers placed on this map.
  final ArgumentCallbacks<Polyline> onPolylineTapped =
  ArgumentCallbacks<Polyline>();

  /// The current set of polylines on this map.
  ///
  /// The returned set will be a detached snapshot of the polylines collection.
  Set<Polyline> get polylines => Set<Polyline>.from(_polylines.values);
  final Map<String, Polyline> _polylines = <String, Polyline>{};

  final _GoogleMapState _googleMapState;

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'camera#onMoveStarted':
        if (_googleMapState.widget.onCameraMoveStarted != null) {
          _googleMapState.widget.onCameraMoveStarted();
        }
        break;
      case 'camera#onMove':
        if (_googleMapState.widget.onCameraMove != null) {
          _googleMapState.widget.onCameraMove(
            CameraPosition.fromMap(call.arguments['position']),
          );
        }
        break;
      case 'camera#onIdle':
        if (_googleMapState.widget.onCameraIdle != null) {
          _googleMapState.widget.onCameraIdle();
        }
        break;
      case 'marker#onTap':
        _googleMapState.onMarkerTap(call.arguments['markerId']);
        break;
      case 'infoWindow#onTap':
        _googleMapState.onInfoWindowTap(call.arguments['markerId']);
        break;
      default:
        throw MissingPluginException();
    }
  }

  /// Updates configuration options of the map user interface.
  ///
  /// Change listeners are notified once the update has been made on the
  /// platform side.
  ///
  /// The returned [Future] completes after listeners have been notified.
  Future<void> _updateMapOptions(Map<String, dynamic> optionsUpdate) async {
    assert(optionsUpdate != null);
    // TODO(amirh): remove this on when the invokeMethod update makes it to stable Flutter.
    // https://github.com/flutter/flutter/issues/26431
    // ignore: strong_mode_implicit_dynamic_method
    await _channel.invokeMethod(
      'map#update',
      <String, dynamic>{
        'options': optionsUpdate,
      },
    );
  }

  /// Updates marker configuration.
  ///
  /// Change listeners are notified once the update has been made on the
  /// platform side.
  ///
  /// The returned [Future] completes after listeners have been notified.
  Future<void> _updateMarkers(_MarkerUpdates markerUpdates) async {
    assert(markerUpdates != null);
    // TODO(amirh): remove this on when the invokeMethod update makes it to stable Flutter.
    // https://github.com/flutter/flutter/issues/26431
    // ignore: strong_mode_implicit_dynamic_method
    await _channel.invokeMethod(
      'markers#update',
      markerUpdates._toMap(),
    );
  }

  /// Starts an animated change of the map camera position.
  ///
  /// The returned [Future] completes after the change has been started on the
  /// platform side.
  Future<void> animateCamera(CameraUpdate cameraUpdate, {double duration = 0.0}) async {
    // TODO(amirh): remove this on when the invokeMethod update makes it to stable Flutter.
    // https://github.com/flutter/flutter/issues/26431
    // ignore: strong_mode_implicit_dynamic_method
    await _channel.invokeMethod('camera#animate', <String, dynamic>{
      'cameraUpdate': cameraUpdate._toJson(),
      'duration': duration
    });
  }

  /// Changes the map camera position.
  ///
  /// The returned [Future] completes after the change has been made on the
  /// platform side.
  Future<void> moveCamera(CameraUpdate cameraUpdate) async {
    // TODO(amirh): remove this on when the invokeMethod update makes it to stable Flutter.
    // https://github.com/flutter/flutter/issues/26431
    // ignore: strong_mode_implicit_dynamic_method
    await _channel.invokeMethod('camera#move', <String, dynamic>{
      'cameraUpdate': cameraUpdate._toJson(),
    });
  }

  Future<VisibleRegion> getVisibleRegion() async {
    dynamic result = await _channel.invokeMethod("map#getVisibleRegion");
    if (result == null) return null;
    return VisibleRegion._fromJson(result);
  }

  Future<bool> isCoordinateOnScreen({@required LatLng position}) async {
    dynamic result = await _channel.invokeMethod("map#isCoordinateOnScreen", <String, dynamic> {
      "lat": position.latitude,
      "lng": position.longitude
    });
    return result;
  }

  /// Set the map style using a json string
  Future<void> setMapStyle(String style) async {
    await _channel.invokeMethod("map#setStyle", <String, dynamic> {
      'style': style
    });
  }

  /// Updates the specified [polyline] with the given [changes]. The polyline must
  /// be a current member of the [polylines] set.
  ///
  /// Change listeners are notified once the polyline has been updated on the
  /// platform side.
  ///
  /// The returned [Future] completes once listeners have been notified.
  Future<void> updatePolyline(
      Polyline polyline, PolylineOptions changes) async {
    assert(polyline != null);
    assert(_polylines[polyline._id] == polyline);
    assert(changes != null);
    changes = polyline._options.copyWith(changes);
    // Code copied from updateMarker
    // ignore: strong_mode_implicit_dynamic_method
    await _channel.invokeMethod('polyline#update', <String, dynamic>{
      'polyline': polyline._id,
      'options': changes._toJson(),
    });
    polyline._options = polyline._options.copyWith(changes);
  }

  /// Adds a polyline to the map, configured using the specified custom [options].
  ///
  /// Change listeners are notified once the polyline has been added on the
  /// platform side.
  ///
  /// The returned [Future] completes with the added polyline once listeners have
  /// been notified.
  Future<Polyline> addPolyline(PolylineOptions options) async {
    final PolylineOptions effectiveOptions =
    PolylineOptions.defaultOptions.copyWith(options);
    final String polylineId = await _channel.invokeMethod(
      'polyline#add',
      <String, dynamic>{
        'options': effectiveOptions._toJson(),
      },
    );
    final Polyline polyline = Polyline(polylineId, effectiveOptions);
    _polylines[polylineId] = polyline;
    return polyline;
  }

  /// Removes the specified [polyline] from the map. The polylines must be a current
  /// member of the [polylines] set.
  ///
  /// Change listeners are notified once the polyline has been removed on the
  /// platform side.
  ///
  /// The returned [Future] completes once listeners have been notified.
  Future<void> removePolyline(Polyline polyline) async {
    assert(polyline != null);
    assert(_polylines[polyline._id] == polyline);
    await _removePolyline(polyline._id);
  }

  /// Helper method to remove a single polyline from the map. Consumed by
  /// [removePolyline] and [clearPolylines].
  ///
  /// The returned [Future] completes once the marker has been removed from
  /// [_polylines].
  Future<void> _removePolyline(String id) async {
    // Code copied from removeMarker
    // ignore: strong_mode_implicit_dynamic_method
    await _channel.invokeMethod('polyline#remove', <String, dynamic>{
      'polyline': id,
    });
    _polylines.remove(id);
  }
}
