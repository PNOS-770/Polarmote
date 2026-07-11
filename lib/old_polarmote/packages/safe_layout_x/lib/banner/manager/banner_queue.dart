import '../model/banner_data.dart';

class BannerQueue {
  BannerQueue({this.maxVisible = 5});

  final int maxVisible;
  final List<BannerData> _activeBanners = <BannerData>[];
  final List<BannerData> _waitingQueue = <BannerData>[];

  List<BannerData> get active => List.unmodifiable(_activeBanners);

  bool contains(String id) {
    return _activeBanners.any((item) => item.id == id) ||
        _waitingQueue.any((item) => item.id == id);
  }

  void push(BannerData data) {
    _removeById(data.id);
    if (_activeBanners.length < maxVisible) {
      _activeBanners.add(data);
      return;
    }
    _waitingQueue.add(data);
  }

  bool update(String id, BannerData Function(BannerData current) mapper) {
    for (var i = 0; i < _activeBanners.length; i++) {
      if (_activeBanners[i].id == id) {
        _activeBanners[i] = mapper(_activeBanners[i]);
        return true;
      }
    }
    for (var i = 0; i < _waitingQueue.length; i++) {
      if (_waitingQueue[i].id == id) {
        _waitingQueue[i] = mapper(_waitingQueue[i]);
        return true;
      }
    }
    return false;
  }

  bool remove(String id) {
    final removedActive = _removeFrom(_activeBanners, id);
    final removedWaiting = _removeFrom(_waitingQueue, id);
    if (!removedActive && !removedWaiting) {
      return false;
    }
    _promoteWaiting();
    return true;
  }

  void clear() {
    _activeBanners.clear();
    _waitingQueue.clear();
  }

  void _removeById(String id) {
    _removeFrom(_activeBanners, id);
    _removeFrom(_waitingQueue, id);
  }

  bool _removeFrom(List<BannerData> list, String id) {
    final index = list.indexWhere((item) => item.id == id);
    if (index < 0) return false;
    list.removeAt(index);
    return true;
  }

  void _promoteWaiting() {
    while (_activeBanners.length < maxVisible && _waitingQueue.isNotEmpty) {
      _activeBanners.add(_waitingQueue.removeAt(0));
    }
  }
}
