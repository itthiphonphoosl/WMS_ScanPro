import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_barcode_listener/flutter_barcode_listener.dart';
import 'package:visibility_detector/visibility_detector.dart';
import '../services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../screens/login_screen.dart';

class ScanStockScreen extends StatefulWidget {
  final String saleOrderNo;
  final String productId;
  final int index;
  final int qty;
  final String location;

  const ScanStockScreen({
    super.key,
    required this.saleOrderNo,
    required this.productId,
    required this.index,
    required this.qty,
    this.location = '',
  });

  @override
  State<ScanStockScreen> createState() => _ScanStockScreenState();
}

class _ScanStockScreenState extends State<ScanStockScreen>
    with WidgetsBindingObserver {
  final TextEditingController _snController = TextEditingController();
  final FocusNode _snFocusNode = FocusNode();

  List<String> scannedSNs = [];
  bool isLoading = false;
  bool _isLoadingSNList = true;
  bool visible = true;
  bool _isManualInput = false; //

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadScannedSNs();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _snController.dispose();
    _snFocusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      FocusManager.instance.primaryFocus?.unfocus();
    }
  }

  Future<void> _loadScannedSNs() async {
    setState(() => _isLoadingSNList = true);

    final allSNs = await ApiService.getAllScannedSNs();
    final filtered =
        allSNs
            .where(
              (sn) =>
                  sn['F_SaleOrderNo'] == widget.saleOrderNo &&
                  sn['F_ProductId'] == widget.productId &&
                  sn['F_Index'].toString() == widget.index.toString(),
            )
            .map((e) => e['F_ProductSN'].toString())
            .toList();

    setState(() {
      scannedSNs = filtered.reversed.toList();
      _isLoadingSNList = false;
    });
  }

  Future<void> _submitSN() async {
    final sn = _snController.text.trim();
    if (sn.isEmpty) return;

    // โหลด SN ทั้งหมดก่อน (อาจ cache ไว้ได้)
    final allSNs = await ApiService.getAllScannedSNs();

    // เช็กว่า SN นี้มีอยู่ในสินค้าอื่นหรือไม่
    final duplicateInOtherProduct = allSNs.any(
      (item) =>
          item['F_ProductSN'].toString() == sn &&
          (item['F_SaleOrderNo'] != widget.saleOrderNo ||
              item['F_ProductId'] != widget.productId ||
              item['F_Index'].toString() != widget.index.toString()),
    );

    if (duplicateInOtherProduct) {
      _snController.clear();
      _showAlert(' SN ซ้ำ', 'SN นี้ถูกสแกนแล้วในสินค้ารายการอื่น');
      return;
    }

    // เช็กว่า SN นี้มีในสินค้านี้แล้ว
    if (scannedSNs.contains(sn)) {
      _snController.clear();
      _showAlert(' SN ซ้ำ', 'SN นี้ถูกสแกนไปแล้ว');
      return;
    }

    setState(() => isLoading = true);

    final result = await ApiService.scanSN(
      saleOrderNo: widget.saleOrderNo,
      productId: widget.productId,
      index: widget.index,
      productSN: sn,
    );

    setState(() => isLoading = false);

    if (result['success'] == true) {
      setState(() {
        scannedSNs.insert(0, sn);
        _snController.clear();
      });
    } else {
      _snController.clear();
      _showAlert('ผิดพลาด', result['message'] ?? 'ไม่สามารถสแกนได้');
    }
  }

  Future<void> _deleteSN(String sn) async {
    setState(() => isLoading = true);

    final result = await ApiService.deleteScannedSN(
      saleOrderNo: widget.saleOrderNo,
      productId: widget.productId,
      index: widget.index,
      productSN: sn,
    );

    if (result['success'] == true) {
      await _loadScannedSNs();
      _showAlert('ลบสำเร็จ', 'ลบ SN เรียบร้อยแล้ว');
    } else {
      _showAlert(' ผิดพลาด', result['message'] ?? 'ไม่สามารถลบได้');
    }

    setState(() => isLoading = false);
  }

  void _confirmDeleteSN(String sn) {
    showDialog(
      context: context,
      builder:
          (_) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.orange),
                SizedBox(width: 8),
                Text('ยืนยันการลบ'),
              ],
            ),
            content: Text('คุณต้องการลบ SN นี้หรือไม่?\n\n$sn'),
            actionsPadding: const EdgeInsets.only(
              bottom: 12,
              right: 12,
              left: 12,
            ), // ✅ ระยะห่างปุ่ม
            actionsAlignment: MainAxisAlignment.end, // ✅ ปุ่มอยู่ชิดกัน
            actions: [
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.deepPurple),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'กลับ',
                  style: TextStyle(color: Colors.deepPurple),
                ),
              ),
              const SizedBox(width: 0),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _deleteSN(sn);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text('ลบ'),
              ),
            ],
          ),
    );
  }

  void _confirmLogout() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('ยืนยันการออกจากระบบ'),
            content: const Text('คุณต้องการออกจากระบบหรือไม่?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('ยกเลิก'),
              ),
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(context); // ปิด dialog ยืนยัน
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.clear();
                  if (!mounted) return;
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                    (route) => false,
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: const Text('ตกลง'),
              ),
            ],
          ),
    );
  }

  void _showAlert(String title, String message, {bool autoClose = true}) {
    bool isDialogOpen = true;

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(
                title.contains('ลบสำเร็จ')
                    ? Icons.check_circle_outline
                    : Icons.info_outline,
                color:
                    title.contains('ลบสำเร็จ') ? Colors.green : Colors.orange,
              ),
              const SizedBox(width: 8),
              Text(title),
            ],
          ),
          content: Text(message),
          actionsPadding: const EdgeInsets.only(bottom: 12, right: 12),
          actionsAlignment: MainAxisAlignment.end,
          actions: [
            OutlinedButton(
              onPressed: () {
                if (isDialogOpen && mounted && Navigator.of(context).canPop()) {
                  isDialogOpen = false;
                  Navigator.of(context).pop();
                }
              },
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                side: const BorderSide(color: Colors.deepPurple),
              ),
              child: const Text(
                'ตกลง',
                style: TextStyle(color: Colors.deepPurple),
              ),
            ),
          ],
        );
      },
    );

    if (autoClose) {
      Future.delayed(const Duration(seconds: 2), () {
        if (isDialogOpen && mounted && Navigator.of(context).canPop()) {
          isDialogOpen = false;
          Navigator.of(context).pop();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scanned = scannedSNs.length;
    final remaining = widget.qty - scanned;
    final isComplete = remaining <= 0;

    return VisibilityDetector(
      key: const Key('visible-detector-key'),
      onVisibilityChanged: (info) {
        visible = info.visibleFraction > 0;

        if (visible) {
          // ✅ ปิดแป้นพิมพ์เมื่อกลับมาหน้าเดิม
          Future.delayed(const Duration(milliseconds: 100), () {
            if (mounted) {
              FocusScope.of(context).unfocus();
            }
          });
        }
      },
      child: BarcodeKeyboardListener(
        bufferDuration: const Duration(milliseconds: 200),
        useKeyDownEvent: !kIsWeb && Platform.isWindows,
        onBarcodeScanned: (barcode) {
          if (!visible || barcode.isEmpty) return;

          SystemChannels.textInput.invokeMethod('TextInput.hide');

          _snController.text = barcode;
          _submitSN();
        },

        child: Stack(
          children: [
            Scaffold(
              backgroundColor: const Color(0xFFffffff),
              appBar: AppBar(
                title: const Text('รายการสินค้า'),
                centerTitle: true,
                backgroundColor: const Color(0xFF1A1A2E),
                foregroundColor: Colors.white,
              ),
              body: RefreshIndicator(
                onRefresh: _loadScannedSNs,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildInfoCard(scanned, remaining, isComplete),
                      const SizedBox(height: 10),
                      if (!isComplete) _buildSNInput(),
                      const SizedBox(height: 10),
                      _buildScannedList(),
                    ],
                  ),
                ),
              ),
            ),
            if (isLoading)
              Container(
                color: Colors.black.withOpacity(0.3),
                child: const Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(int scanned, int remaining, bool isComplete) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'รหัสสินค้า : ${widget.productId}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildInfoBox(
                  'จำนวนเบิก',
                  widget.qty.toString(),
                  Colors.orange,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildInfoBox(
                  'ยิง SN แล้ว',
                  scanned.toString(),
                  Colors.green,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildInfoBox(
                  'ยังไม่ได้ยิง',
                  remaining.toString(),
                  Colors.red,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          isComplete
              ? _statusTag('✅ สแกนครบแล้ว', Colors.green)
              : _statusTag('⌛ รอสแกน SN', Colors.redAccent),
        ],
      ),
    );
  }

  Widget _buildInfoBox(String title, String value, Color textColor) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 10, color: Colors.black87),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusTag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildSNInput() {
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _snController.text.isEmpty
                  ? 'สแกน SN เท่านั้น'
                  : _snController.text,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ),
        const SizedBox(width: 8),
        ElevatedButton(
          onPressed: isLoading ? null : _submitSN,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1A1A2E),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          child: const Icon(Icons.qr_code_scanner, size: 18),
        ),
      ],
    );
  }

  Widget _buildScannedList() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'SN ที่สแกนแล้ว',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          _isLoadingSNList
              ? const Center(child: CircularProgressIndicator())
              : scannedSNs.isEmpty
              ? const Center(child: Text('ไม่มีรายการที่สแกน'))
              : ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: scannedSNs.length,
                itemBuilder: (context, index) {
                  final sn = scannedSNs[index];
                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            sn,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          height: 24,
                          width: 24,
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: Colors.red.shade200,
                              width: 1,
                            ),
                          ),
                          child: IconButton(
                            icon: const Icon(
                              Icons.delete,
                              size: 14,
                              color: Colors.red,
                            ),
                            onPressed: () => _confirmDeleteSN(sn),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            splashRadius: 18,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
        ],
      ),
    );
  }
}
