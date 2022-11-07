part of maplibre_gl;

abstract class AnnotationManager<T extends Annotation> {
  final MaplibreMapController controller;
  final _idToAnnotation = <String, T>{};
  final _idToLayerIndex = <String, int>{};

  /// Called if a annotation is tapped
  final void Function(T)? onTap;

  /// base id of the manager. User [layerdIds] to get the actual ids.
  final String id;

  List<String> get layerIds =>
      [for (int i = 0; i < allLayerProperties.length; i++) _makeLayerId(i)];

  /// If disabled the manager offers no interaction for the created symbols
  final bool enableInteraction;

  /// implemented to define the layer properties
  List<LayerProperties> get allLayerProperties;

  /// used to spedicy the layer and annotation will life on
  /// This can be replaced by layer filters a soon as they are implemented
  final int Function(T)? selectLayer;

  /// get the an annotation by its id
  T? byId(String id) => _idToAnnotation[id];

  Set<T> get annotations => _idToAnnotation.values.toSet();

  AnnotationManager(this.controller,
      {this.onTap, this.selectLayer, required this.enableInteraction})
      : id = getRandomString() {
    for (var i = 0; i < allLayerProperties.length; i++) {
      final layerId = _makeLayerId(i);
      controller.addGeoJsonSource(layerId, buildFeatureCollection([]),
          promoteId: "id");
      controller.addLayer(layerId, layerId, allLayerProperties[i]);
    }

    if (onTap != null) {
      controller.onFeatureTapped.add(_onFeatureTapped);
    }
    controller.onFeatureDrag.add(_onDrag);
  }

  /// This function can be used to rebuild all layers after their properties
  /// changed
  Future<void> _rebuildLayers() async {
    for (var i = 0; i < allLayerProperties.length; i++) {
      final layerId = _makeLayerId(i);
      await controller.removeLayer(layerId);
      await controller.addLayer(layerId, layerId, allLayerProperties[i]);
    }
  }

  /// This function is a temporary fix due to the layer order not currently
  /// handled by the flutter adapter
  Future<void> rebuildLayers() async {
    await _rebuildLayers();
  }

  _onFeatureTapped(dynamic id, Point<double> point, LatLng coordinates) {
    final annotation = _idToAnnotation[id];
    if (annotation != null) {
      onTap!(annotation);
    }
  }

  String _makeLayerId(int layerIndex) => "${id}_$layerIndex";

  Future<void> _setAll() async {
    if (selectLayer != null) {
      final featureBuckets = [for (final _ in allLayerProperties) <T>[]];

      for (final annotation in _idToAnnotation.values) {
        final layerIndex = selectLayer!(annotation);
        _idToLayerIndex[annotation.id] = layerIndex;
        featureBuckets[layerIndex].add(annotation);
      }

      for (var i = 0; i < featureBuckets.length; i++) {
        await controller.setGeoJsonSource(
            _makeLayerId(i),
            buildFeatureCollection(
                [for (final l in featureBuckets[i]) l.toGeoJson()]));
      }
    } else {
      await controller.setGeoJsonSource(
          _makeLayerId(0),
          buildFeatureCollection(
              [for (final l in _idToAnnotation.values) l.toGeoJson()]));
    }
  }

  /// Adds a multiple annotations to the map. This much faster than calling add
  /// multiple times
  Future<void> _addAllAnnotations(Iterable<T> annotations) async {
    for (var a in annotations) {
      _idToAnnotation[a.id] = a;
    }
    await _setAll();
  }

  /// add a single annotation to the map
  Future<void> _addAnnotation(T annotation) async {
    _idToAnnotation[annotation.id] = annotation;
    await _setAll();
  }

  /// Removes multiple annotations from the map
  Future<void> _removeAllAnnotations(Iterable<T> annotations) async {
    for (var a in annotations) {
      _idToAnnotation.remove(a.id);
    }
    await _setAll();
  }

  /// Remove a single annotation form the map
  Future<void> _removeAnnotation(T annotation) async {
    _idToAnnotation.remove(annotation.id);
    await _setAll();
  }

  /// Removes all annotations from the map
  Future<void> _clearAnnotations() async {
    _idToAnnotation.clear();

    await _setAll();
  }

  /// Fully dipose of all the the resouces managed by the annotation manager.
  /// The manager cannot be used after this has been called
  void dispose() async {
    _idToAnnotation.clear();
    await _setAll();
    for (var i = 0; i < allLayerProperties.length; i++) {
      await controller.removeLayer(_makeLayerId(i));
      await controller.removeSource(_makeLayerId(i));
    }
  }

  _onDrag(dynamic id,
      {required Point<double> point,
      required LatLng origin,
      required LatLng current,
      required LatLng delta,
      required DragEventType eventType}) {
    final annotation = byId(id);
    if (annotation != null) {
      annotation.translate(delta);
      _set(annotation);
    }
  }

  /// Set an existing anntotation to the map. Use this to do a fast update for a
  /// single annotation
  Future<void> _set(T anntotation) async {
    assert(_idToAnnotation.containsKey(anntotation.id),
        "you can only set existing annotations");
    _idToAnnotation[anntotation.id] = anntotation;
    final oldLayerIndex = _idToLayerIndex[anntotation.id];
    final layerIndex = selectLayer != null ? selectLayer!(anntotation) : 0;
    if (oldLayerIndex != layerIndex) {
      // if the annotation has to be moved to another layer/source we have to
      // set all
      await _setAll();
    } else {
      await controller.setGeoJsonFeature(
          _makeLayerId(layerIndex), anntotation.toGeoJson());
    }
  }
}

class LineManager extends AnnotationLayer<Line, LineOptions> with ChangeNotifier {
  LineManager(MaplibreMapController controller,
      {void Function(Line)? onTap, bool enableInteraction = true})
      : super(
          controller,
          onTap: onTap,
          enableInteraction: enableInteraction,
          selectLayer: (Line line) => line.options.linePattern == null ? 0 : 1,
        );

  static const _baseProperties = LineLayerProperties(
    lineJoin: [Expressions.get, 'lineJoin'],
    lineOpacity: [Expressions.get, 'lineOpacity'],
    lineColor: [Expressions.get, 'lineColor'],
    lineWidth: [Expressions.get, 'lineWidth'],
    lineGapWidth: [Expressions.get, 'lineGapWidth'],
    lineOffset: [Expressions.get, 'lineOffset'],
    lineBlur: [Expressions.get, 'lineBlur'],
  );

  @override
  List<LayerProperties> get allLayerProperties => [
        _baseProperties,
        _baseProperties.copyWith(
            LineLayerProperties(linePattern: [Expressions.get, 'linePattern'])),
      ];

  @override
  Future<Line> add(LineOptions options, [Map? data]) async {
    final effectiveOptions = LineOptions.defaultOptions.copyWith(options);
    final line = Line(getRandomString(), effectiveOptions, data);
    await _addAnnotation(line);
    notifyListeners();
    return line;
  }

  @override
  Future<List<Line>> addAll(List<LineOptions> options, [List<Map>? data]) async {
    final lines = [
      for (var i = 0; i < options.length; i++)
        Line(getRandomString(), LineOptions.defaultOptions.copyWith(options[i]),
            data?[i])
    ];
    await _addAllAnnotations(lines);

    notifyListeners();
    return lines;
  }

  @override
  Future<void> clear() async {
    await _clearAnnotations();
    notifyListeners();
  }

  @override
  Future<void> remove(Line line) async {
    await _removeAnnotation(line);
    notifyListeners();
  }

  @override
  Future<void> removeAll(Iterable<Line> lines) async {
    await _removeAllAnnotations(lines);
    notifyListeners();
  }

  @override
  Future<void> update(Line line, LineOptions options) async {
    line.options = line.options.copyWith(options);
    await _set(line);
    notifyListeners();
  }

  List<LatLng> getPosition(Line line) {
    return line.options.geometry!;
  }

}

class FillManager extends AnnotationLayer<Fill, FillOptions> with ChangeNotifier {
  FillManager(
    MaplibreMapController controller, {
    void Function(Fill)? onTap,
    bool enableInteraction = true,
  }) : super(
          controller,
          onTap: onTap,
          enableInteraction: enableInteraction,
          selectLayer: (Fill fill) => fill.options.fillPattern == null ? 0 : 1,
        );
  @override
  List<LayerProperties> get allLayerProperties => const [
        FillLayerProperties(
          fillOpacity: [Expressions.get, 'fillOpacity'],
          fillColor: [Expressions.get, 'fillColor'],
          fillOutlineColor: [Expressions.get, 'fillOutlineColor'],
        ),
        FillLayerProperties(
          fillOpacity: [Expressions.get, 'fillOpacity'],
          fillColor: [Expressions.get, 'fillColor'],
          fillOutlineColor: [Expressions.get, 'fillOutlineColor'],
          fillPattern: [Expressions.get, 'fillPattern'],
        )
      ];

  @override
  Future<Fill> add(FillOptions options, [Map? data]) async {
    final FillOptions effectiveOptions =
    FillOptions.defaultOptions.copyWith(options);
    final fill = Fill(getRandomString(), effectiveOptions, data);
    await _addAnnotation(fill);
    notifyListeners();
    return fill;
  }

  @override
  Future<List<Fill>> addAll(List<FillOptions> options, [List<Map>? data]) async {
    final fills = [
      for (var i = 0; i < options.length; i++)
        Fill(getRandomString(), FillOptions.defaultOptions.copyWith(options[i]),
            data?[i])
    ];
    await _addAllAnnotations(fills);

    notifyListeners();
    return fills;
  }

  @override
  Future<void> clear() async {
    await _clearAnnotations();

    notifyListeners();
  }

  @override
  Future<void> remove(Fill fill) async {
    await _removeAnnotation(fill);
    notifyListeners();
  }

  @override
  Future<void> removeAll(Iterable<Fill> fills) async {
    await _removeAllAnnotations(fills);
    notifyListeners();
  }

  @override
  Future<void> update(Fill fill, FillOptions options) async {
    fill.options = fill.options.copyWith(options);
    await _set(fill);
    notifyListeners();
  }
}

class CircleManager extends AnnotationLayer<Circle, CircleOptions> with ChangeNotifier {
  CircleManager(
    MaplibreMapController controller, {
    void Function(Circle)? onTap,
    bool enableInteraction = true,
  }) : super(
          controller,
          enableInteraction: enableInteraction,
          onTap: onTap,
        );
  @override
  List<LayerProperties> get allLayerProperties => const [
        CircleLayerProperties(
          circleRadius: [Expressions.get, 'circleRadius'],
          circleColor: [Expressions.get, 'circleColor'],
          circleBlur: [Expressions.get, 'circleBlur'],
          circleOpacity: [Expressions.get, 'circleOpacity'],
          circleStrokeWidth: [Expressions.get, 'circleStrokeWidth'],
          circleStrokeColor: [Expressions.get, 'circleStrokeColor'],
          circleStrokeOpacity: [Expressions.get, 'circleStrokeOpacity'],
        )
      ];

  @override
  Future<Circle> add(CircleOptions options, [Map? data]) async {
    final CircleOptions effectiveOptions =
    CircleOptions.defaultOptions.copyWith(options);
    final circle = Circle(getRandomString(), effectiveOptions, data);
    await _addAnnotation(circle);
    notifyListeners();
    return circle;
  }

  @override
  Future<List<Circle>> addAll(List<CircleOptions> options, [List<Map>? data]) async {
    final cricles = [
      for (var i = 0; i < options.length; i++)
        Circle(getRandomString(),
            CircleOptions.defaultOptions.copyWith(options[i]), data?[i])
    ];
    await _addAllAnnotations(cricles);

    notifyListeners();
    return cricles;
  }

  @override
  Future<void> clear() async {
    await _clearAnnotations();

    notifyListeners();
  }

  @override
  Future<void> remove(Circle circle) async {
    await _removeAnnotation(circle);

    notifyListeners();
  }

  @override
  Future<void> removeAll(Iterable<Circle> circles) async {
    await _removeAllAnnotations(circles);
    notifyListeners();
  }

  @override
  Future<void> update(Circle circle, CircleOptions options) async {
    circle.options = circle.options.copyWith(options);
    await _set(circle);

    notifyListeners();
  }

  LatLng getPosition(Circle circle) {
    return circle.options.geometry!;
  }
}

class SymbolManager extends AnnotationLayer<Symbol, SymbolOptions> with ChangeNotifier {
  SymbolManager(
    MaplibreMapController controller, {
    void Function(Symbol)? onTap,
    bool iconAllowOverlap = false,
    bool textAllowOverlap = false,
    bool iconIgnorePlacement = false,
    bool textIgnorePlacement = false,
    bool enableInteraction = true,
  })  : _iconAllowOverlap = iconAllowOverlap,
        _textAllowOverlap = textAllowOverlap,
        _iconIgnorePlacement = iconIgnorePlacement,
        _textIgnorePlacement = textIgnorePlacement,
        super(
          controller,
          enableInteraction: enableInteraction,
          onTap: onTap,
        );

  bool _iconAllowOverlap;
  bool _textAllowOverlap;
  bool _iconIgnorePlacement;
  bool _textIgnorePlacement;

  /// For more information on what this does, see https://docs.mapbox.com/help/troubleshooting/optimize-map-label-placement/#label-collision
  Future<void> setIconAllowOverlap(bool value) async {
    _iconAllowOverlap = value;
    await _rebuildLayers();
  }

  /// For more information on what this does, see https://docs.mapbox.com/help/troubleshooting/optimize-map-label-placement/#label-collision
  Future<void> setTextAllowOverlap(bool value) async {
    _textAllowOverlap = value;
    await _rebuildLayers();
  }

  /// For more information on what this does, see https://docs.mapbox.com/help/troubleshooting/optimize-map-label-placement/#label-collision
  Future<void> setIconIgnorePlacement(bool value) async {
    _iconIgnorePlacement = value;
    await _rebuildLayers();
  }

  /// For more information on what this does, see https://docs.mapbox.com/help/troubleshooting/optimize-map-label-placement/#label-collision
  Future<void> setTextIgnorePlacement(bool value) async {
    _textIgnorePlacement = value;
    await _rebuildLayers();
  }

  @override
  List<LayerProperties> get allLayerProperties => [
        SymbolLayerProperties(
          iconSize: [Expressions.get, 'iconSize'],
          iconImage: [Expressions.get, 'iconImage'],
          iconRotate: [Expressions.get, 'iconRotate'],
          iconOffset: [Expressions.get, 'iconOffset'],
          iconAnchor: [Expressions.get, 'iconAnchor'],
          iconOpacity: [Expressions.get, 'iconOpacity'],
          iconColor: [Expressions.get, 'iconColor'],
          iconHaloColor: [Expressions.get, 'iconHaloColor'],
          iconHaloWidth: [Expressions.get, 'iconHaloWidth'],
          iconHaloBlur: [Expressions.get, 'iconHaloBlur'],
          // note that web does not support setting this in a fully data driven
          // way this is a upstream issue
          textFont: kIsWeb
              ? null
              : [
                  Expressions.caseExpression,
                  [Expressions.has, 'fontNames'],
                  [Expressions.get, 'fontNames'],
                  [
                    Expressions.literal,
                    ["Open Sans Regular", "Arial Unicode MS Regular"]
                  ],
                ],
          textField: [Expressions.get, 'textField'],
          textSize: [Expressions.get, 'textSize'],
          textMaxWidth: [Expressions.get, 'textMaxWidth'],
          textLetterSpacing: [Expressions.get, 'textLetterSpacing'],
          textJustify: [Expressions.get, 'textJustify'],
          textAnchor: [Expressions.get, 'textAnchor'],
          textRotate: [Expressions.get, 'textRotate'],
          textTransform: [Expressions.get, 'textTransform'],
          textOffset: [Expressions.get, 'textOffset'],
          textOpacity: [Expressions.get, 'textOpacity'],
          textColor: [Expressions.get, 'textColor'],
          textHaloColor: [Expressions.get, 'textHaloColor'],
          textHaloWidth: [Expressions.get, 'textHaloWidth'],
          textHaloBlur: [Expressions.get, 'textHaloBlur'],
          symbolSortKey: [Expressions.get, 'zIndex'],
          iconAllowOverlap: _iconAllowOverlap,
          iconIgnorePlacement: _iconIgnorePlacement,
          textAllowOverlap: _textAllowOverlap,
          textIgnorePlacement: _textIgnorePlacement,
        )
      ];

  @override
  Future<Symbol> add(SymbolOptions options, [Map? data]) async {
    final effectiveOptions = SymbolOptions.defaultOptions.copyWith(options);
    final symbol = Symbol(getRandomString(), effectiveOptions, data);
    await _addAnnotation(symbol);
    notifyListeners();
    return symbol;
  }

  @override
  Future<List<Symbol>> addAll(List<SymbolOptions> options, [List<Map>? data]) async {
    final symbols = [
      for (var i = 0; i < options.length; i++)
        Symbol(getRandomString(),
            SymbolOptions.defaultOptions.copyWith(options[i]), data?[i])
    ];
    await _addAllAnnotations(symbols);

    notifyListeners();
    return symbols;
  }

  @override
  Future<void> clear() async {
    await _clearAnnotations();
    notifyListeners();
  }

  @override
  Future<void> remove(Symbol symbol) async {
    await _removeAnnotation(symbol);
    notifyListeners();
  }

  @override
  Future<void> removeAll(Iterable<Symbol> symbols) async {
    await _removeAllAnnotations(symbols);
    notifyListeners();
  }

  @override
  Future<void> update(Symbol symbol, SymbolOptions options) async {
    await _set(symbol..options = symbol.options.copyWith(options));

    notifyListeners();
  }

  LatLng getPosition(Symbol symbol) {
    return symbol.options.geometry!;
  }
}
