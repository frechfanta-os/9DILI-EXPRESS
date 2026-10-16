import 'package:cloud_firestore/cloud_firestore.dart';

/// Statuts possibles d'une offre (bid) de shoppeur.
class BidStatus {
  static const String pending = 'pending';
  static const String accepted = 'accepted';
  static const String rejected = 'rejected';

  static const List<String> all = [pending, accepted, rejected];
}

/// Modèle pour la sous-collection : /errands/{errandId}/bids/{bidId}.
class ErrandBidModel {
  final String bidId;
  final String shopperId;
  final String shopperName;
  final double shopperRating;
  final double proposedCommission;
  final String status; // 'pending', 'accepted', 'rejected'
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const ErrandBidModel({
    required this.bidId,
    required this.shopperId,
    required this.shopperName,
    this.shopperRating = 5.0,
    required this.proposedCommission,
    this.status = BidStatus.pending,
    this.createdAt,
    this.updatedAt,
  });

  bool get isPending => status == BidStatus.pending;
  bool get isAccepted => status == BidStatus.accepted;
  bool get isRejected => status == BidStatus.rejected;

  factory ErrandBidModel.fromMap(
    Map<String, dynamic> data, {
    String? documentId,
  }) {
    return ErrandBidModel(
      bidId: documentId ?? data['bidId'] ?? '',
      shopperId: data['shopperId'] ?? '',
      shopperName: data['shopperName'] ?? '',
      shopperRating: (data['shopperRating'] as num?)?.toDouble() ?? 5.0,
      proposedCommission:
          (data['proposedCommission'] as num?)?.toDouble() ?? 0.0,
      status: data['status'] ?? BidStatus.pending,
      createdAt: (data['createdAt'] is Timestamp)
          ? (data['createdAt'] as Timestamp).toDate()
          : null,
      updatedAt: (data['updatedAt'] is Timestamp)
          ? (data['updatedAt'] as Timestamp).toDate()
          : null,
    );
  }

  factory ErrandBidModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? {};
    return ErrandBidModel.fromMap(data, documentId: snapshot.id);
  }

  Map<String, dynamic> toMap() {
    return {
      'bidId': bidId,
      'shopperId': shopperId,
      'shopperName': shopperName,
      'shopperRating': shopperRating,
      'proposedCommission': proposedCommission,
      'status': status,
      'createdAt': createdAt != null
          ? Timestamp.fromDate(createdAt!)
          : FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  ErrandBidModel copyWith({
    String? bidId,
    String? shopperId,
    String? shopperName,
    double? shopperRating,
    double? proposedCommission,
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ErrandBidModel(
      bidId: bidId ?? this.bidId,
      shopperId: shopperId ?? this.shopperId,
      shopperName: shopperName ?? this.shopperName,
      shopperRating: shopperRating ?? this.shopperRating,
      proposedCommission: proposedCommission ?? this.proposedCommission,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() {
    return 'ErrandBidModel(id: $bidId, shopper: $shopperName, rating: $shopperRating, commission: $proposedCommission, status: $status)';
  }
}
