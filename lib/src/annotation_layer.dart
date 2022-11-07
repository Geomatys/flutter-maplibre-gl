part of maplibre_gl;


abstract class AnnotationLayer<T extends Annotation, O> extends AnnotationManager<T> {



  AnnotationLayer(MaplibreMapController controller, {void Function(T)? onTap, bool enableInteraction = false, int Function(T)? selectLayer})
      : super(controller, onTap: onTap, enableInteraction: enableInteraction, selectLayer: selectLayer) {

  }

  Future<T> add(O options, [Map? data]);
  Future<List<T>> addAll(List<O> options, [List<Map>? data]);
  Future<void> update(T elem, O options);
  Future<void> remove(T elem);
  Future<void> removeAll(Iterable<T> elem);
  Future<void> clear();


}
