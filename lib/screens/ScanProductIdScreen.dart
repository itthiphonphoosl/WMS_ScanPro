import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_barcode_listener/flutter_barcode_listener.dart';
import '../services/api_service.dart';
import 'package:intl/intl.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'searchproduct.dart';

class ScanProductIdScreen extends StatefulWidget {
  final Map<String, dynamic>? initialProduct;
  final GlobalKey<ScaffoldState>? scaffoldKey; // ✅ เพิ่มตรงนี้

  const ScanProductIdScreen({Key? key, this.initialProduct, this.scaffoldKey})
    : super(key: key);

  @override
  State<ScanProductIdScreen> createState() => _ScanProductIdScreenState();
}

class _ScanProductIdScreenState extends State<ScanProductIdScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final List<Map<String, dynamic>> _resultList = [];
  bool _isLoading = false;
  String? _employeeId;
  bool _isInDialogMode = false;
  bool _hasLoadedFromSearch = false;
  bool _isManualInput = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_hasLoadedFromSearch) {
      _hasLoadedFromSearch = true;
      _loadScannedProductFromSearch(); // ✅ โหลดทุกครั้งเมื่อกลับมาหน้านี้
    }
  }

  @override
  void initState() {
    super.initState();

    _loadEmployeeId();

    // ✅ โหลดจาก shared preferences หลัง build เสร็จ
    Future.delayed(Duration.zero, () {
      _loadScannedProductFromSearch();
    });

    if (widget.initialProduct != null) {
      _resultList.add(widget.initialProduct!);
    }
  }

  Future<void> _loadScannedProductFromSearch() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('scannedProducts');

    if (saved != null) {
      final decoded = jsonDecode(saved) as List<dynamic>;
      if (decoded.isNotEmpty) {
        final selected = decoded.first as Map<String, dynamic>;

        setState(() {
          _resultList
            ..clear()
            ..add(selected);
        });

        //อย่าลบ prefs ที่นี่
      }
    }
  }

  Future<void> _loadEmployeeId() async {
    final prefs = await SharedPreferences.getInstance();
    final loadedId = prefs.getString('employeeId') ?? 'UNKNOWN';
    setState(() => _employeeId = loadedId);
  }

  Future<void> _loadSavedScans() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('scannedProducts');
    if (saved != null) {
      final decoded = jsonDecode(saved) as List<dynamic>;
      setState(() {
        _resultList.addAll(decoded.cast<Map<String, dynamic>>());
      });
    }
  }

  Future<void> _scanProduct([String? manualId]) async {
    setState(() => _isManualInput = false);
    if (_isInDialogMode) return;

    final keyword = manualId?.trim() ?? _controller.text.trim();
    if (keyword.isEmpty) return;

    if (!mounted) return;
    setState(() => _isLoading = true);
    _isManualInput = false;

    try {
      final data = await ApiService.scanProductId(keyword);

      if (!mounted) return;

      if (data.isNotEmpty) {
        final casted = data.cast<Map<String, dynamic>>();

        setState(() {
          _resultList
            ..clear()
            ..add(casted.first);
        });

        // ✅ ลบ SharedPreferences ตอนสแกนใหม่
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('scannedProducts');

        await _saveScannedList();
      } else {
        _showProductAlertDialog(
          title: 'ไม่พบสินค้า',
          message: 'ไม่พบข้อมูลสินค้าสำหรับ: $keyword',
          icon: Icons.info_outline,
          color: Colors.orange,
        );
      }
    } catch (_) {
      _showProductAlertDialog(
        title: 'เกิดข้อผิดพลาด',
        message: 'ไม่พบข้อมูลสินค้า',
        icon: Icons.info_outline,
        color: Colors.red,
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _controller.clear();
      });
    }
  }

  Future<void> _saveScannedList() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(_resultList);
    await prefs.setString('scannedProducts', encoded);
  }

  void _showProductAlertDialog({
    required String title,
    required String message,
    IconData icon = Icons.info_outline,
    Color color = Colors.deepPurple,
    bool autoClose = true,
    Duration duration = const Duration(seconds: 2),
  }) {
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
              Icon(icon, color: color),
              const SizedBox(width: 8),
              Expanded(child: Text(title)),
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
      Future.delayed(duration, () {
        if (isDialogOpen && mounted && Navigator.of(context).canPop()) {
          isDialogOpen = false;
          Navigator.of(context).pop();
        }
      });
    }
  }

  void _showChangeLocationDialog(String productId) {
    final TextEditingController _locationController = TextEditingController();
    final FocusNode _focusNode = FocusNode();
    _isInDialogMode = true;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return BarcodeKeyboardListener(
          onBarcodeScanned: (barcode) {
            _locationController.text =
                barcode; // ✅ อัปเดตช่อง TextField ด้วยค่าที่สแกน
            Navigator.pop(context);
            _confirmLocation(productId, barcode);
          },

          bufferDuration: const Duration(milliseconds: 200),
          child: AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: double.infinity,
                  child: Text(
                    'เปลี่ยนสถานที่',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Color(0xFF1B1F2B),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _locationController,
                  focusNode: _focusNode,
                  readOnly: true,
                  decoration: InputDecoration(
                    hintText: 'กรอก/สแกน สถานที่ใหม่',
                    hintStyle: const TextStyle(fontSize: 13),
                    filled: true,
                    fillColor: const Color(0xFFF5F5F5),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
                    suffixIcon: const Icon(Icons.qr_code_scanner, size: 20),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onSubmitted: (value) {
                    Navigator.pop(context);
                    _confirmLocation(productId, value);
                  },
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('ยกเลิก'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _confirmLocation(
                          productId,
                          _locationController.text.trim(),
                        );
                      },
                      child: const Text('ยืนยัน'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    ).then((_) {
      _isInDialogMode = false;
    });
  }

  Future<void> _confirmLocation(String productId, String location) async {
    final newLocation = location.trim();

    if (newLocation.isEmpty) return;

    try {
      final result = await ApiService.changeLocation(
        productId: productId,
        newLocation: newLocation,
        employeeId: _employeeId ?? 'UNKNOWN',
      );

      if (!mounted) return;

      setState(() {
        final index = _resultList.indexWhere(
          (item) => item['F_ProductId'] == productId,
        );
        if (index != -1) {
          _resultList[index]['F_Location'] = newLocation;
        }
      });

      if (mounted) {
        _showProductAlertDialog(
          title: ' แจ้งเตือน',
          message: result['message'] ?? 'เปลี่ยนสถานที่สำเร็จ',
          icon: Icons.check_circle_outline,
          color: Colors.green,
          autoClose: true,
        );
        await _saveScannedList();
      }
    } catch (_) {
      if (mounted) {
        _showProductAlertDialog(
          title: ' เกิดผิดพลาด',
          message: 'ไม่พบสถานที่ในระบบ',
          autoClose: true,
          icon: Icons.error_outline,
          color: Colors.red,
        );
      }
    }
  }

  Widget _buildResultList() {
    if (_resultList.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 20),
        child: Text('ยังไม่มีรายการที่สแกน'),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _resultList.length,
      itemBuilder: (context, index) {
        final item = _resultList[index];
        final imagePath = item['imagePath']?.toString() ?? '';

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 4,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${item['F_ProductId'] ?? '-'}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Color(0xFF1B1F2B),
                  ),
                ),
                const SizedBox(height: 6),

                Text(
                  'ชื่อสินค้า : ${item['F_ProductName'] ?? '-'}',
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 12),

                Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: 300,
                      height: 220,
                      child:
                          imagePath.isNotEmpty
                              ? Image.network(
                                imagePath,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return Image.asset(
                                    'assets/images/pp.png',
                                    fit: BoxFit.cover,
                                  );
                                },
                              )
                              : Image.asset(
                                'assets/images/products.png',
                                fit: BoxFit.cover,
                              ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.only(right: 4),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          children: [
                            const Text(
                              'จำนวน',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 4),

                            AutoSizeText(
                              '${NumberFormat('#,###').format(item['F_StockBalance'] ?? 0)} ${item['F_UnitName'] ?? ''}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF008000),
                              ),
                              maxLines: 1,
                              minFontSize: 10, // 👈 ปรับขนาดต่ำสุดได้
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.only(left: 4),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          children: [
                            const Text(
                              'Location',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 4),
                            AutoSizeText(
                              item['F_Location'] ?? '-',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF00008B),
                              ),
                              maxLines: 1,
                              minFontSize: 10,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton.icon(
                    onPressed:
                        () => _showChangeLocationDialog(item['F_ProductId']),
                    icon: const Icon(Icons.edit_location_alt),
                    label: const Text('เปลี่ยนสถานที่'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1B1F2B),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BarcodeKeyboardListener(
      bufferDuration: const Duration(milliseconds: 200),
      onBarcodeScanned: (barcode) {
        if (barcode.trim().isEmpty) return;

        SystemChannels.textInput.invokeMethod('TextInput.hide');

        FocusScope.of(context).unfocus();
        setState(() => _isManualInput = false);

        _scanProduct(barcode); // ✅ เรียกยิงค้นหา
      },
      child: Builder(
        builder:
            (context) => Scaffold(
              backgroundColor: const Color(0xFFffffff),
              appBar: AppBar(
                backgroundColor: const Color(0xFF1B1F2B),
                foregroundColor: Colors.white,
                centerTitle: true,
                leading: IconButton(
                  icon: const Icon(Icons.menu),
                  onPressed:
                      () =>
                          widget.scaffoldKey?.currentState
                              ?.openDrawer(), // ✅ ใช้ key จาก MainNavigation
                ),

                title: const Text(
                  'เปลี่ยนสถานที่',
                  style: TextStyle(
                    fontWeight: FontWeight.normal,
                    color: Colors.white,
                  ),
                ),

                actions: [
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    tooltip: 'รีเฟรชข้อมูล',
                    onPressed: () async {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.remove('scannedProducts');
                      setState(() {
                        _resultList.clear();
                      });
                    },
                  ),
                ],
              ),
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 40,
                            alignment: Alignment.centerLeft,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _controller.text.isEmpty
                                  ? 'ค้นหาชื่อสินค้า หรือสแกน ProductID'
                                  : _controller.text,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ),

                        const SizedBox(width: 6),
                        Container(
                          height: 40,
                          width: 40,
                          decoration: BoxDecoration(
                            color: const Color(0xFF1B1F2B),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: IconButton(
                            icon: const Icon(
                              Icons.qr_code_scanner,
                              size: 20,
                              color: Colors.white,
                            ),
                            padding: EdgeInsets.zero,
                            onPressed: _scanProduct,
                            tooltip: 'สแกน / ค้นหา',
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          height: 40,
                          width: 40,
                          decoration: BoxDecoration(
                            color: const Color(0xFF1B1F2B),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: IconButton(
                            icon: const Icon(
                              Icons.search,
                              size: 20,
                              color: Colors.white,
                            ),
                            padding: EdgeInsets.zero,
                            onPressed: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder:
                                      (context) => const SearchProductScreen(),
                                ),
                              );
                              await _loadScannedProductFromSearch(); // โหลดสินค้าที่เลือกกลับมาแสดง
                            },

                            tooltip: 'ค้นหา',
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 10),

                    if (_isLoading) const CircularProgressIndicator(),

                    _buildResultList(),
                  ],
                ),
              ),
            ),
      ),
    );
  }
}
