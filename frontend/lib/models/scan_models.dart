class FaceBox {
  final double top;
  final double right;
  final double bottom;
  final double left;

  FaceBox({
    required this.top,
    required this.right,
    required this.bottom,
    required this.left,
  });

  factory FaceBox.fromJson(Map<String, dynamic> json) {
    return FaceBox(
      top: (json['top'] as num?)?.toDouble() ?? 0.0,
      right: (json['right'] as num?)?.toDouble() ?? 0.0,
      bottom: (json['bottom'] as num?)?.toDouble() ?? 0.0,
      left: (json['left'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class LeaderScanItem {
  final int faceIndex;
  final bool identified;
  final double confidence;
  final FaceBox box;
  final Map<String, dynamic>? reportCard;

  LeaderScanItem({
    required this.faceIndex,
    required this.identified,
    required this.confidence,
    required this.box,
    this.reportCard,
  });

  factory LeaderScanItem.fromJson(Map<String, dynamic> json) {
    return LeaderScanItem(
      faceIndex: (json['face_index'] as num?)?.toInt() ?? 0,
      identified: json['identified'] == true,
      confidence: (json['confidence_percentage'] as num?)?.toDouble() ?? 0.0,
      box: FaceBox.fromJson(
        json['box'] is Map ? Map<String, dynamic>.from(json['box']) : {},
      ),
      reportCard: json['report_card'] is Map
          ? Map<String, dynamic>.from(json['report_card'])
          : null,
    );
  }
}
