import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:barcode_scan2/barcode_scan2.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:convert';
import 'package:retry/retry.dart';
import 'package:home_mart/error_handler.dart'; // Assumed to contain error dialog functions

// A dedicated model class for a tax row to ensure data integrity and stability.
class TaxRow {
  String chargeType;
  String? accountHead;
  String description;
  double rate;
  List<String> sourceItemCodes;
  bool isManual;

  // UI-specific state is managed within the model.
  final TextEditingController rateController;
  final TextEditingController amountController;
  final TextEditingController descriptionController;
  final TextEditingController accountHeadController;
  final GlobalKey targetKey;
  final LayerLink layerLink;

  TaxRow({
    required this.chargeType,
    this.accountHead,
    required this.description,
    required this.rate,
    required this.sourceItemCodes,
    required this.isManual,
  })  : rateController = TextEditingController(text: (chargeType != 'Actual' ? rate : 0.0).toStringAsFixed(2)),
        amountController = TextEditingController(text: (chargeType == 'Actual' ? rate : 0.0).toStringAsFixed(2)),
        descriptionController = TextEditingController(text: description),
        accountHeadController = TextEditingController(text: description),
        targetKey = GlobalKey(),
        layerLink = LayerLink();

  // Helper method to dispose all controllers, preventing memory leaks.
  void dispose() {
    rateController.dispose();
    amountController.dispose();
    descriptionController.dispose();
    accountHeadController.dispose();
  }
}


class QuotationScreen extends StatefulWidget {
  final String serverUrl;
  final String sid;
  final Map<String, dynamic>? initialData;
  const QuotationScreen({
    Key? key,
    required this.serverUrl,
    required this.sid,
    this.initialData,
  }) : super(key: key);
  @override
  _QuotationScreenState createState() => _QuotationScreenState();
}

class _QuotationScreenState extends State<QuotationScreen> {
  final _formKey = GlobalKey<FormState>();
  List<dynamic> _itemsList = [];
  List<dynamic> _customersList = [];
  List<dynamic> _salespersonsList = [];
  List<Map<String, dynamic>> _selectedItems = [];
  List<dynamic> _salesTaxTemplates = [];
  List<dynamic> _accountHeads = [];
  dynamic _selectedCustomer;
  dynamic _selectedSalesperson;
  String _selectedTaxCategory = 'Inter State';
  // The list of custom taxes now uses the robust TaxRow model.
  List<TaxRow> _customTaxes = [];
  bool _isLoading = true;
  final _quotationToController = TextEditingController(text: 'Customer');
  DateTime _transactionDate = DateTime.now();
  double _cachedTotalAmount = 0.0;
  double _cachedGrandTotal = 0.0;
  int _cachedTotalQuantity = 0;
  List<Map<String, dynamic>> _calculatedTaxes = [];
  String _namingSeries = 'SAL-QTN-.YYYY';
  String _sellingPriceList = 'Standard Selling';
  String _currency = 'INR';

  final Set<String> _manuallyRemovedTaxes = {};
  final List<String> _uomList = ['Nos', 'Unit', 'Box', 'Pair', 'Set', 'Meter', 'Kg', 'Ltr', 'Pcs'];
  final List<String> _taxChargeTypes = ['On Net Total', 'Actual', 'On Previous Row Amount', 'On Previous Row Total', 'On Item Quantity'];
  final List<String> _taxCategoryOptions = ['Inter State', 'Outer State'];
  OverlayEntry? _overlayEntry;
  final TextEditingController _accountSearchController = TextEditingController();
  List<dynamic> _filteredAccountHeads = [];
  int? _activeTaxDropdownIndex;

  @override
  void initState() {
    super.initState();
    _accountSearchController.addListener(() {
      _filterAccountHeads(_accountSearchController.text);
    });
    _initializeData();
  }

  @override
  void dispose() {
    _quotationToController.dispose();
    for (var item in _selectedItems) {
      item['quantityController']?.dispose();
      item['discountPercentController']?.dispose();
      item['discountAmountController']?.dispose();
    }
    // Properly dispose controllers for each tax row.
    for (var tax in _customTaxes) {
      tax.dispose();
    }
    _accountSearchController.dispose();
    _removeOverlay();
    super.dispose();
  }

  Future<void> _initializeData() async {
    setState(() => _isLoading = true);
    await Future.wait([
      _fetchItems(),
      _fetchCustomers(),
      _fetchSalespersons(),
      _fetchSalesTaxesTemplates(),
      _fetchAccountHeads(),
    ]);
    _loadInitialData();
    setState(() {
      _isLoading = false;
      _filteredAccountHeads = _accountHeads;
    });
  }

  void _loadInitialData() {
    if (widget.initialData != null) {
      final data = widget.initialData!;
      _quotationToController.text = data['quotation_to']?.toString() ?? 'Customer';
      _transactionDate = DateTime.tryParse(data['transaction_date']?.toString() ?? '') ?? DateTime.now();
      _selectedTaxCategory = data['tax_category'] ?? 'Inter State';

      _selectedItems = List<Map<String, dynamic>>.from(
        (data['items'] as List<dynamic>?)?.map((item) {
              final fullItemData = _itemsList.firstWhere(
                (i) => i['item_code'] == item['item_code'],
                orElse: () => {'taxes': []},
              );
              return {
                'item_name': item['item_name']?.toString() ?? 'Unknown',
                'item_code': item['item_code']?.toString() ?? '',
                'quantity': item['qty'] is num ? item['qty'].toInt() : 1,
                'uom': item['uom']?.toString() ?? 'Nos',
                'conversion_factor': (item['conversion_factor'] as num?)?.toDouble() ?? 0.0,
                'price_list_rate': (item['price_list_rate'] as num?)?.toDouble() ?? 0.0,
                'discount_percent': (item['discount_percentage'] as num?)?.toDouble() ?? 0.0,
                'discount_amount': (item['discount_amount'] as num?)?.toDouble() ?? 0.0,
                'amount': _calculateItemAmount(item),
                'image': item['image']?.toString(),
                'barcode': _parseBarcodeFromItem(item),
                'taxes': item['taxes'] ?? fullItemData['taxes'] ?? [],
                'quantityController': TextEditingController(text: (item['qty'] ?? 1).toString()),
                'discountPercentController': TextEditingController(
                  text: ((item['discount_percentage'] ?? 0.0) as num).toDouble().toStringAsFixed(2),
                ),
                'discountAmountController': TextEditingController(
                  text: ((item['discount_amount'] ?? 0.0) as num).toDouble().toStringAsFixed(2),
                ),
                'selectedUom': item['uom']?.toString() ?? 'Nos',
              };
            }) ?? [],
      );

      final customerNameFromData = data['customer']?.toString() ?? data['customer_name']?.toString();
      if (customerNameFromData != null) {
        _selectedCustomer = _customersList.firstWhere(
          (customer) => customer['name'] == customerNameFromData,
          orElse: () => {
            'name': customerNameFromData,
            'customer_name': customerNameFromData,
            'tax_category': 'Inter State',
          },
        );
        _selectedTaxCategory = _selectedCustomer?['tax_category'] ?? 'Inter State';
      }

      _selectedSalesperson = data['sales_person'] != null
          ? _salespersonsList.firstWhere(
              (sp) => sp['salesperson_name'] == data['sales_person'],
              orElse: () => {'salesperson_name': data['sales_person']},
            )
          : null;

      final Map<String, List<String>> itemGeneratedTaxSources = {};
      for (final item in _selectedItems) {
        final itemCode = item['item_code'] as String;
        final fullItemData = _itemsList.firstWhere((i) => i['item_code'] == itemCode, orElse: () => {'taxes': []});
        final List<dynamic> itemTaxes = fullItemData['taxes'] ?? [];
        for (var itemTaxInfo in itemTaxes) {
          if (itemTaxInfo['tax_category'] == _selectedTaxCategory) {
            final String? templateName = itemTaxInfo['item_tax_template'];
            if (templateName == null) continue;
            final selectedTemplate = _salesTaxTemplates.firstWhere((t) => t['template_name'] == templateName, orElse: () => null);
            if (selectedTemplate != null && selectedTemplate['taxes'] != null) {
              for (var taxComponent in selectedTemplate['taxes']) {
                final accountHeadName = taxComponent['account_head']?.toString() ?? '';
                if (accountHeadName.isNotEmpty) {
                  itemGeneratedTaxSources.putIfAbsent(accountHeadName, () => []).add(itemCode);
                }
              }
            }
          }
        }
      }

      if (data['taxes'] != null && (data['taxes'] as List).isNotEmpty) {
        _customTaxes = List<TaxRow>.from(
          (data['taxes'] as List<dynamic>).map((savedTax) {
            final accountHeadName = savedTax['account_head']?.toString();
            final sources = itemGeneratedTaxSources[accountHeadName] ?? [];
            final isManual = sources.isEmpty;
            final account = _accountHeads.firstWhere((h) => h['name'] == accountHeadName, orElse: () => {'account_name': accountHeadName});
            final displayName = account['account_name'] ?? accountHeadName ?? '';
            final chargeType = savedTax['charge_type']?.toString() ?? 'On Net Total';
            final rate = (savedTax['rate'] as num?)?.toDouble() ?? 0.0;
            
            return TaxRow(
              chargeType: chargeType,
              accountHead: accountHeadName,
              description: displayName,
              rate: rate,
              sourceItemCodes: sources,
              isManual: isManual,
            );
          }),
        );
      }
      _performCalculations();
    }
  }

  String _parseBarcodeFromItem(dynamic item) {
    String barcodeValue = item['barcode']?.toString() ?? '';
    if (barcodeValue.startsWith('<svg') && barcodeValue.contains('data-barcode-value=')) {
      final RegExp regExp = RegExp(r'data-barcode-value="([^"]*)"');
      final match = regExp.firstMatch(barcodeValue);
      if (match != null && match.groupCount >= 1) {
        return match.group(1)!;
      }
    }
    return barcodeValue;
  }

  Map<String, String> _getHeaders() => {
        'Cookie': 'sid=${widget.sid}',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  Future<dynamic> _fetchData(String endpoint, {bool isCustomMethod = true}) async {
    final url = isCustomMethod
        ? "${widget.serverUrl}/api/method/$endpoint"
        : "${widget.serverUrl}/api/resource/$endpoint";
    try {
      final response = await retry(
        () => http.get(Uri.parse(url), headers: _getHeaders()),
        maxAttempts: 3,
        delayFactor: const Duration(seconds: 1),
      );
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        if (!mounted) return null;
        showApiErrorDialog(context, statusCode: response.statusCode, message: response.body);
        return null;
      }
    } catch (e) {
      if (!mounted) return null;
      showErrorDialog(context, 'Network Error', 'Failed to fetch data from $endpoint: $e');
      return null;
    }
  }

  Future<void> _fetchItems() async {
    final data = await _fetchData("custom_scripts.API.qtn.get_item_details");
    if (data != null && data['message'] != null && mounted) {
      setState(() => _itemsList = data['message'] as List<dynamic>);
    }
  }

  Future<void> _fetchCustomers() async {
    final data = await _fetchData("custom_scripts.API.qtn.get_customers");
    if (data != null && data['message'] != null && mounted) {
      setState(() => _customersList = data['message'] as List<dynamic>);
    }
  }

  Future<void> _fetchSalespersons() async {
    final data = await _fetchData("custom_scripts.API.qtn.get_salesperson");
    if (data != null && data['message'] != null && mounted) {
      setState(() {
        _salespersonsList = (data['message'] as List<dynamic>)
            .map((item) => {'salesperson_name': item['sales_person_name']?.toString() ?? ''})
            .toList();
      });
    }
  }

  Future<void> _fetchSalesTaxesTemplates() async {
    final data = await _fetchData("custom_scripts.API.qtn.get_all_sales_taxes_templates1");
    if (data != null && data['message'] != null && mounted) {
      setState(() => _salesTaxTemplates = data['message'] as List<dynamic>);
    }
  }

  Future<void> _fetchAccountHeads() async {
    final data = await _fetchData("custom_scripts.API.qtn.get_accounts");
    if (data != null && data['message'] != null && mounted) {
      setState(() => _accountHeads = data['message'] as List<dynamic>);
    } else {
      if (!mounted) return;
      showErrorDialog(context, 'Fetch Error', 'Failed to load account heads.');
    }
  }

  Future<void> _scanBarcode() async {
    if (await Permission.camera.request().isGranted) {
      try {
        final result = await BarcodeScanner.scan();
        if (!mounted) return;

        if (result.type == ResultType.Barcode) {
          final barcode = result.rawContent;
          final item = _itemsList.firstWhere(
            (item) => _parseBarcodeFromItem(item) == barcode,
            orElse: () => null,
          );
          if (item != null) {
            _addItemToResult(item);
          } else {
            if (!mounted) return;
            showErrorDialog(context, 'Item Not Found', 'No item found for barcode: $barcode');
          }
        }
      } catch (e) {
        if (!mounted) return;
        showErrorDialog(context, 'Barcode Scan Error', 'Failed to scan barcode: $e');
      }
    } else {
      if (!mounted) return;
      showErrorDialog(context, 'Permission Denied', 'Camera permission denied');
    }
  }

  void _addItemToResult(dynamic item) {
    setState(() {
      final String defaultUom = item['stock_uom']?.toString() ?? 'Nos';
      if (!_uomList.contains(defaultUom)) {
        _uomList.add(defaultUom);
      }
      
      _selectedItems.add({
        'item_name': item['item_name'] ?? 'Unknown',
        'item_code': item['item_code'] ?? '',
        'quantity': 1,
        'uom': defaultUom,
        'conversion_factor': (item['conversion_factor'] as num?)?.toDouble() ?? 0.0,
        'price_list_rate': (item['price_list_rate'] as num?)?.toDouble() ?? 0.0,
        'discount_percent': 0.0,
        'discount_amount': 0.0,
        'amount': (item['price_list_rate'] as num?)?.toDouble() ?? 0.0,
        'image': item['image'],
        'barcode': _parseBarcodeFromItem(item),
        'taxes': item['taxes'] ?? [],
        'quantityController': TextEditingController(text: '1'),
        'discountPercentController': TextEditingController(text: '0.00'),
        'discountAmountController': TextEditingController(text: '0.00'),
        'selectedUom': defaultUom,
      });

      final List<dynamic> itemTaxes = item['taxes'] ?? [];
      for (var itemTaxInfo in itemTaxes) {
        if (itemTaxInfo['tax_category'] == _selectedTaxCategory) {
          final String? templateName = itemTaxInfo['item_tax_template'];
          if (templateName == null) continue;
          
          final selectedTemplate = _salesTaxTemplates.firstWhere((t) => t['template_name'] == templateName, orElse: () => null);
          
          if (selectedTemplate != null && selectedTemplate['taxes'] != null) {
            for (var taxComponent in selectedTemplate['taxes']) {
              _addOrUpdateTaxFromItem(taxComponent, item['item_code']);
            }
          }
        }
      }
      _performCalculations();
    });
  }

  void _addOrUpdateTaxFromItem(Map<String, dynamic> taxComponent, String itemCode) {
    final accountHeadName = taxComponent['account_head']?.toString() ?? '';
    if (accountHeadName.isEmpty) return;

    if (_manuallyRemovedTaxes.contains(accountHeadName)) {
      return;
    }

    final existingTaxIndex = _customTaxes.indexWhere((t) => t.accountHead == accountHeadName);
    
    if (existingTaxIndex != -1) {
      final tax = _customTaxes[existingTaxIndex];
      if (!tax.sourceItemCodes.contains(itemCode)) {
        tax.sourceItemCodes.add(itemCode);
      }
    } else {
      final account = _accountHeads.firstWhere((h) => h['name'] == accountHeadName, orElse: () => {'account_name': accountHeadName});
      final displayName = account['account_name'] ?? accountHeadName;
      final chargeType = taxComponent['charge_type'] ?? 'On Net Total';
      final rate = (taxComponent['rate'] as num?)?.toDouble() ?? 0.0;
      
      final newTax = TaxRow(
        chargeType: chargeType,
        accountHead: accountHeadName,
        description: displayName,
        rate: rate,
        sourceItemCodes: [itemCode],
        isManual: false,
      );
      _customTaxes.add(newTax);
    }
  }

  double _calculateItemAmount(Map<String, dynamic> item) {
    double price = (item['price_list_rate'] as num?)?.toDouble() ?? 0.0;
    final qty = (item['quantity'] as num?)?.toInt() ?? 1;
    final discount = (item['discount_amount'] as num?)?.toDouble() ?? 0.0;
    return (price * qty - discount).clamp(0.0, double.infinity);
  }

  void _updateItem(int index, {String? quantity, String? discountPercent, String? discountAmount, String? uom}) {
    setState(() {
      final item = _selectedItems[index];
      
      if (quantity != null) {
        item['quantity'] = int.tryParse(quantity) ?? 1;
        if (item['quantity'] <= 0) {
          _removeItem(index);
          return;
        }
      }
      
      final price = item['price_list_rate'] as double;
      final currentQty = item['quantity'] as int;
      
      if (discountPercent != null) {
        final percent = double.tryParse(discountPercent) ?? 0.0;
        item['discount_percent'] = percent;
        final newDiscountAmount = (price * currentQty * percent / 100);
        item['discount_amount'] = newDiscountAmount;
        final newText = newDiscountAmount.toStringAsFixed(2);
        item['discountAmountController'].value = TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: newText.length),
        );
      } else if (discountAmount != null) {
        final amount = double.tryParse(discountAmount) ?? 0.0;
        final subtotal = price * currentQty;
        item['discount_amount'] = amount;
        final newDiscountPercent = subtotal > 0 ? (amount / subtotal * 100) : 0.0;
        item['discount_percent'] = newDiscountPercent;
        final newText = newDiscountPercent.toStringAsFixed(2);
        item['discountPercentController'].value = TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: newText.length),
        );
      }
      
      if (uom != null) item['selectedUom'] = uom;
      
      item['amount'] = _calculateItemAmount(item);
      _performCalculations();
    });
  }

  void _removeItem(int index) {
    if (index < 0 || index >= _selectedItems.length) return;

    setState(() {
      final itemCodeToRemove = _selectedItems[index]['item_code'];

      _selectedItems[index]['quantityController']?.dispose();
      _selectedItems[index]['discountPercentController']?.dispose();
      _selectedItems[index]['discountAmountController']?.dispose();
      
      _selectedItems.removeAt(index);

      final taxesToKeep = <TaxRow>[];
      final taxesToRemove = <TaxRow>[];

      for (final tax in _customTaxes) {
        if (tax.isManual) {
          taxesToKeep.add(tax);
        } else {
          tax.sourceItemCodes.remove(itemCodeToRemove);
          if (tax.sourceItemCodes.isNotEmpty) {
            taxesToKeep.add(tax);
          } else {
            taxesToRemove.add(tax);
          }
        }
      }

      for (final tax in taxesToRemove) {
        tax.dispose();
      }

      _customTaxes = taxesToKeep;
      
      _performCalculations();
    });
  }

  void _addCustomTaxRow() {
    setState(() {
      final newTax = TaxRow(
        chargeType: 'On Net Total',
        accountHead: null,
        description: '',
        rate: 0.0,
        isManual: true,
        sourceItemCodes: [],
      );
      _customTaxes.add(newTax);
    });
  }

  void _updateCustomTaxRow(int index, {String? type, String? accountHead, String? rate}) {
    if (index < 0 || index >= _customTaxes.length) return;

    setState(() {
      final tax = _customTaxes[index];
      
      if (type != null) {
        tax.chargeType = type;
        if (type == 'Actual') {
          tax.rate = 0.0;
          tax.rateController.text = '0.00';
        }
      }
      
      if (accountHead != null) {
        tax.accountHead = accountHead;
        final selectedAccount = _accountHeads.firstWhere((acc) => acc['name'] == accountHead, orElse: () => {'account_name': accountHead});
        final accountName = selectedAccount['account_name'] ?? accountHead;
        tax.description = accountName;
        tax.descriptionController.text = accountName;
        tax.accountHeadController.text = accountName;
      }
      
      if (rate != null) {
        final rateValue = double.tryParse(rate) ?? 0.0;
        tax.rate = rateValue;
      }
      
      _performCalculations();
    });
  }

  void _removeCustomTaxRow(int index) {
    _removeOverlay();
    
    setState(() {
      if (index < 0 || index >= _customTaxes.length) return;

      final tax = _customTaxes[index];

      if (!tax.isManual && tax.accountHead != null && tax.accountHead!.isNotEmpty) {
        _manuallyRemovedTaxes.add(tax.accountHead!);
      }

      tax.dispose();
      _customTaxes.removeAt(index);

      if (_activeTaxDropdownIndex != null) {
        if (_activeTaxDropdownIndex == index) {
          _activeTaxDropdownIndex = null;
        } else if (_activeTaxDropdownIndex! > index) {
          _activeTaxDropdownIndex = _activeTaxDropdownIndex! - 1;
        }
      }

      _performCalculations();
    });
  }

  void _removeOverlay() {
    if (_overlayEntry != null) {
      try {
        _overlayEntry!.remove();
      } catch (e) {
        print('Error removing overlay: $e');
      }
      _overlayEntry = null;
      _activeTaxDropdownIndex = null;
    }
  }

  void _showAccountHeadOverlay(BuildContext context, int taxIndex) {
    if (_accountHeads.isEmpty) {
      if (!mounted) return;
      showErrorDialog(context, 'No Account Heads', 'No account heads available.');
      return;
    }
    
    _removeOverlay();
    setState(() => _activeTaxDropdownIndex = taxIndex);

    final taxData = _customTaxes[taxIndex];
    final targetContext = taxData.targetKey.currentContext;

    if (targetContext == null) {
      if (!mounted) return;
      showErrorDialog(context, 'Render Error', 'Cannot display dropdown.');
      return;
    }

    final renderBox = targetContext.findRenderObject() as RenderBox;
    final size = renderBox.size;
    _filteredAccountHeads = _accountHeads;
    _accountSearchController.clear();

    _overlayEntry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => setState(() => _removeOverlay()),
              behavior: HitTestBehavior.translucent,
            ),
          ),
          Positioned(
            width: size.width,
            child: CompositedTransformFollower(
              link: taxData.layerLink,
              showWhenUnlinked: false,
              offset: Offset(0, size.height),
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 200),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: TextField(
                          controller: _accountSearchController,
                          autofocus: true,
                          decoration: _inputDecoration('Search Account...'),
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                      Expanded(
                        child: _filteredAccountHeads.isEmpty
                            ? const Padding(
                                padding: EdgeInsets.all(8.0),
                                child: Text('No accounts found', style: TextStyle(color: Colors.grey)),
                              )
                            : ListView.builder(
                                padding: EdgeInsets.zero,
                                shrinkWrap: true,
                                itemCount: _filteredAccountHeads.length,
                                itemBuilder: (context, index) {
                                  final account = _filteredAccountHeads[index];
                                  final accountName = account['account_name'] ?? account['name'] ?? 'Unknown';
                                  return ListTile(
                                    title: Text(accountName, style: const TextStyle(fontSize: 14), overflow: TextOverflow.ellipsis),
                                    onTap: () {
                                      _updateCustomTaxRow(taxIndex, accountHead: account['name']);
                                      _removeOverlay();
                                    },
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    
    if (mounted) {
      Overlay.of(context).insert(_overlayEntry!);
    }
  }

  void _filterAccountHeads(String query) {
    if (_overlayEntry == null) return;
    setState(() {
      _filteredAccountHeads = query.isEmpty
          ? _accountHeads
          : _accountHeads.where((account) {
              final accountName = (account['account_name'] ?? account['name'] ?? '').toString().toLowerCase();
              return accountName.contains(query.toLowerCase());
            }).toList();
    });
    _overlayEntry?.markNeedsBuild();
  }

  void _performCalculations() {
    _cachedTotalQuantity = _selectedItems.fold(0, (sum, item) => sum + (item['quantity'] as int));
    _cachedTotalAmount = _selectedItems.fold(0.0, (sum, item) => sum + (item['amount'] as double));

    List<Map<String, dynamic>> tempCalculatedTaxes = [];
    double grandTotalTax = 0.0;

    for (var tax in _customTaxes) {
      double taxableAmount = 0.0;
      double taxAmountForComponent = 0.0;
      double valueToSaveForBackend;

      if (!tax.isManual) {
        for (var item in _selectedItems) {
          if (tax.sourceItemCodes.contains(item['item_code'])) {
            taxableAmount += (item['amount'] as double);
          }
        }
      } else {
        taxableAmount = _cachedTotalAmount;
      }

      double inputRate = double.tryParse(tax.rateController.text) ?? tax.rate;

      if (tax.chargeType == 'Actual') {
        taxAmountForComponent = inputRate;
        valueToSaveForBackend = taxAmountForComponent;
      } else {
        taxAmountForComponent = (taxableAmount * inputRate / 100);
        valueToSaveForBackend = inputRate;
      }

      final newText = taxAmountForComponent.toStringAsFixed(2);
      tax.amountController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: newText.length),
      );

      grandTotalTax += taxAmountForComponent;

      tempCalculatedTaxes.add({
        'description': tax.description,
        'charge_type': tax.chargeType,
        'account_head': tax.accountHead,
        'tax_amount': taxAmountForComponent,
        'rate': valueToSaveForBackend,
      });
    }

    _calculatedTaxes = tempCalculatedTaxes;
    _cachedGrandTotal = _cachedTotalAmount + grandTotalTax;
  }

  Future<void> _selectDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _transactionDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) setState(() => _transactionDate = picked);
  }

  Future<void> _saveQuotation() async {
    _removeOverlay();
    if (!mounted || !_formKey.currentState!.validate()) return;
    
    if (_selectedCustomer == null) {
      showErrorDialog(context, 'Validation Error', 'Please select a customer.');
      return;
    }
    if (_selectedSalesperson == null) {
      showErrorDialog(context, 'Validation Error', 'Please select a salesperson.');
      return;
    }
    if (_selectedItems.isEmpty) {
      showErrorDialog(context, 'Validation Error', 'Please add at least one item.');
      return;
    }
    for (var tax in _customTaxes) {
      if (tax.accountHead == null || tax.accountHead!.isEmpty) {
        showErrorDialog(context, 'Validation Error', 'Please select an account head for all tax rows.');
        return;
      }
    }

    setState(() => _isLoading = true);

    final itemsToSave = _selectedItems.map((item) => {
          'item_code': item['item_code'],
          'item_name': item['item_name'],
          'qty': item['quantity'],
          'uom': item['selectedUom'],
          'conversion_factor': item['conversion_factor'],
          'price_list_rate': item['price_list_rate'],
          'discount_percentage': item['discount_percent'],
          'discount_amount': item['discount_amount'],
          'amount': item['amount'],
          'barcode': item['barcode'],
          'taxes': item['taxes'],
          'cost_center': 'Main - NG',
        }).toList();

    final taxesToSave = _calculatedTaxes.map((tax) {
      return {
        'account_head': tax['account_head'],
        'charge_type': tax['charge_type'],
        'description': tax['description'],
        'rate': tax['rate'],
      };
    }).toList();

    final Map<String, dynamic> quotationData = {
      'quotation_to': _quotationToController.text.isEmpty ? 'Customer' : _quotationToController.text,
      'customer': _selectedCustomer['name']?.toString() ?? '',
      'party_name': _selectedCustomer['customer_name']?.toString() ?? '',
      'sales_person': _selectedSalesperson['salesperson_name']?.toString() ?? '',
      'transaction_date': DateFormat('yyyy-MM-dd').format(_transactionDate),
      'status': widget.initialData?['status']?.toString() ?? 'Draft',
      'items': itemsToSave,
      'taxes': taxesToSave,
      'tax_category': _selectedTaxCategory,
      'cost_center': 'Main - NG',
      'naming_series': _namingSeries,
      'selling_price_list': _sellingPriceList,
      'currency': _currency,
      if (widget.initialData != null && widget.initialData!['name'] != null)
        'name': widget.initialData!['name'],
    };

    try {
      final http.Response response;
      if (widget.initialData == null || widget.initialData!['name'] == null) {
        response = await retry(() => http.post(Uri.parse("${widget.serverUrl}/api/resource/Quotation"), headers: _getHeaders(), body: json.encode({"data": quotationData})), maxAttempts: 3);
      } else {
        response = await retry(() => http.put(Uri.parse("${widget.serverUrl}/api/resource/Quotation/${widget.initialData!['name']}"), headers: _getHeaders(), body: json.encode({"data": quotationData})), maxAttempts: 3);
      }

      if (!mounted) return;

      if (response.statusCode == 200 || response.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.initialData == null ? 'Quotation created successfully!' : 'Quotation updated successfully!'), backgroundColor: Colors.green));
        Navigator.pop(context, true);
      } else {
        showApiErrorDialog(context, statusCode: response.statusCode, message: response.body);
      }
    } catch (e) {
      if (!mounted) return;
      showErrorDialog(context, 'Operation Failed', 'Failed to save quotation: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE0F7FA),
      appBar: AppBar(
        title: Text(widget.initialData == null ? 'Create Quotation' : 'Edit Quotation', style: const TextStyle(fontFamily: 'Dubai', color: Colors.white)),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(8.0),
                children: [
                  _buildSectionHeader(context, 'General Information'),
                  _buildDateField(context),
                  const SizedBox(height: 8),
                  _buildSectionHeader(context, 'Parties'),
                  _buildCustomerSelector(),
                  const SizedBox(height: 8),
                  _buildTaxCategoryDropdown(),
                  const SizedBox(height: 8),
                  _buildSalespersonSelector(),
                  const SizedBox(height: 8),
                  _buildSectionHeader(context, 'Item Details'),
                  _buildItemAdder(),
                  if (_selectedItems.isNotEmpty) _buildItemsList(),
                  const SizedBox(height: 8),
                  _buildSectionHeader(context, 'Accounting & Taxes'),
                  _buildTaxesTable(),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ElevatedButton.icon(
                      onPressed: _addCustomTaxRow,
                      icon: const Icon(Icons.add),
                      label: const Text('Add Custom Tax Row'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildTotalsCard(),
                  const SizedBox(height: 16),
                  _buildSaveButton(),
                ],
              ),
            ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Theme.of(context).primaryColor, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildDateField(BuildContext context) {
    return GestureDetector(
      onTap: () => _selectDate(context),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: _boxDecoration(),
        child: Row(
          children: [
            const Icon(Icons.calendar_today, color: Color(0xFF005BAC)),
            const SizedBox(width: 6),
            Expanded(child: Text(DateFormat('yyyy-MM-dd').format(_transactionDate))),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerSelector() {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () async {
              _removeOverlay();
              final selected = await showSearch(context: context, delegate: CustomerSearchDelegate(_customersList));
              if (!mounted) return;
              if (selected != null) {
                setState(() {
                  _selectedCustomer = selected;
                  _selectedTaxCategory = selected['tax_category'] ?? 'Inter State';
                  _performCalculations();
                });
              }
            },
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: _boxDecoration(),
              child: Row(
                children: [
                  const Icon(Icons.person, color: Color(0xFF005BAC)),
                  const SizedBox(width: 6),
                  Expanded(child: Text(_selectedCustomer?['customer_name'] ?? 'Select Customer', overflow: TextOverflow.ellipsis)),
                  const Icon(Icons.arrow_drop_down, color: Colors.grey),
                ],
              ),
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.add_circle_outline, color: Color(0xFF005BAC), size: 25),
          onPressed: () async {
            _removeOverlay();
            final newCustomer = await showDialog<Map<String, dynamic>>(context: context, builder: (context) => CustomerCreationDialog(serverUrl: widget.serverUrl, sid: widget.sid));
            if (!mounted) return;
            if (newCustomer != null) {
              await _fetchCustomers();
              if (!mounted) return;
              setState(() {
                _selectedCustomer = _customersList.firstWhere((c) => c['name'] == newCustomer['name'], orElse: () => newCustomer);
                _selectedTaxCategory = newCustomer['tax_category'] ?? 'Inter State';
                _performCalculations();
              });
            }
          },
        ),
      ],
    );
  }

  Widget _buildTaxCategoryDropdown() {
    return DropdownButtonFormField<String>(
      value: _selectedTaxCategory,
      decoration: _inputDecoration('Tax Category'),
      items: _taxCategoryOptions.map((String category) => DropdownMenuItem<String>(value: category, child: Text(category))).toList(),
      onChanged: (newValue) => setState(() {
        _selectedTaxCategory = newValue!;
        _performCalculations();
      }),
      validator: (value) => value == null ? 'Tax category is required' : null,
    );
  }

  Widget _buildSalespersonSelector() {
    return GestureDetector(
      onTap: () async {
        _removeOverlay();
        final selected = await showSearch(context: context, delegate: SalespersonSearchDelegate(_salespersonsList));
        if (!mounted) return;
        if (selected != null) setState(() => _selectedSalesperson = selected);
      },
      child: Container(
        padding: const EdgeInsets.all(10.0),
        decoration: _boxDecoration(),
        child: Row(
          children: [
            const Icon(Icons.people_alt, color: Color(0xFF005BAC)),
            const SizedBox(width: 6),
            Expanded(child: Text(_selectedSalesperson?['salesperson_name'] ?? 'Select Salesperson', overflow: TextOverflow.ellipsis)),
            const Icon(Icons.arrow_drop_down, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _buildTaxesTable() {
    if (_customTaxes.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
        child: const Center(child: Text('No taxes added yet', style: TextStyle(color: Colors.grey, fontSize: 14))),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Container(
        decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
        child: Table(
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          columnWidths: const {0: FixedColumnWidth(120), 1: FixedColumnWidth(180), 2: FixedColumnWidth(140), 3: FixedColumnWidth(80), 4: FixedColumnWidth(80), 5: FixedColumnWidth(60)},
          children: [
            _buildTaxTableHeader(),
            ..._customTaxes.asMap().entries.map((entry) => _buildTaxTableRow(entry.key, entry.value)),
          ],
        ),
      ),
    );
  }

  TableRow _buildTaxTableHeader() {
    const style = TextStyle(fontWeight: FontWeight.bold, fontSize: 12);
    return const TableRow(
      decoration: BoxDecoration(color: Color(0xFFB3E5FC), borderRadius: BorderRadius.only(topLeft: Radius.circular(8), topRight: Radius.circular(8))),
      children: [
        Padding(padding: EdgeInsets.all(8.0), child: Text('Type', style: style, textAlign: TextAlign.center)),
        Padding(padding: EdgeInsets.all(8.0), child: Text('Account Head', style: style, textAlign: TextAlign.center)),
        Padding(padding: EdgeInsets.all(8.0), child: Text('Description', style: style, textAlign: TextAlign.center)),
        Padding(padding: EdgeInsets.all(8.0), child: Text('Rate ', style: style, textAlign: TextAlign.center)),
        Padding(padding: EdgeInsets.all(8.0), child: Text('Amount', style: style, textAlign: TextAlign.center)),
        Padding(padding: EdgeInsets.all(8.0), child: Text('Action', style: style)),
      ],
    );
  }

  TableRow _buildTaxTableRow(int index, TaxRow tax) {
    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.all(4.0),
          child: DropdownButtonFormField<String>(
            value: tax.chargeType,
            decoration: _inputDecoration(null),
            isExpanded: true,
            items: _taxChargeTypes.map((t) => DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis))).toList(),
            onChanged: (v) {
              if (v != null) _updateCustomTaxRow(index, type: v);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(4.0),
          child: CompositedTransformTarget(
            key: tax.targetKey,
            link: tax.layerLink,
            child: TextFormField(
              controller: tax.accountHeadController,
              readOnly: true,
              decoration: _inputDecoration(null).copyWith(errorText: tax.accountHead == null ? 'Required' : null, suffixIcon: const Icon(Icons.arrow_drop_down, color: Colors.grey)),
              onTap: () => _showAccountHeadOverlay(context, index),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(4.0),
          child: TextFormField(
            controller: tax.descriptionController,
            readOnly: true,
            decoration: _inputDecoration(null).copyWith(filled: true, fillColor: Colors.grey.shade200),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(4.0),
          child: TextFormField(
            controller: tax.rateController,
            readOnly: !tax.isManual,
            decoration: _inputDecoration(null).copyWith(filled: !tax.isManual, fillColor: !tax.isManual ? Colors.grey.shade200 : Colors.white),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.center,
            onChanged: (v) {
              if (tax.isManual) _updateCustomTaxRow(index, rate: v);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(4.0),
          child: TextFormField(
            controller: tax.amountController,
            readOnly: true,
            decoration: _inputDecoration(null).copyWith(filled: true, fillColor: Colors.grey.shade200),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.center,
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(4.0),
          child: SizedBox(
            width: 40,
            child: IconButton(
              icon: Icon(Icons.delete_outline, color: Colors.red.shade600, size: 20),
              onPressed: () {
                if (!tax.isManual) {
                  showDialog(
                    context: context,
                    builder: (BuildContext context) {
                      return AlertDialog(
                        title: const Text('Delete Tax'),
                        content: Text('Are you sure you want to delete "${tax.description}"?\n\nThis tax was added automatically from an item.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
                          TextButton(
                            onPressed: () {
                              Navigator.of(context).pop();
                              _removeCustomTaxRow(index);
                            },
                            child: const Text('Delete', style: TextStyle(color: Colors.red)),
                          ),
                        ],
                      );
                    },
                  );
                } else {
                  _removeCustomTaxRow(index);
                }
              },
              tooltip: 'Delete Tax Row',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildItemAdder() {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () async {
              _removeOverlay();
              final selected = await showSearch(context: context, delegate: ItemSearchDelegate(items: _itemsList, serverUrl: widget.serverUrl));
              if (!mounted) return;
              if (selected != null) _addItemToResult(selected);
            },
            child: Container(
              padding: const EdgeInsets.all(10.0),
              decoration: _boxDecoration(),
              child: const Row(
                children: [
                  Icon(Icons.add_shopping_cart, color: Color(0xFF005BAC)),
                  SizedBox(width: 6),
                  Expanded(child: Text('Add Item')),
                ],
              ),
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.qr_code_scanner, color: Color(0xFF005BAC), size: 25),
          onPressed: () {
            _removeOverlay();
            _scanBarcode();
          },
        ),
      ],
    );
  }

  Widget _buildItemsList() {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _selectedItems.length,
      itemBuilder: (context, index) {
        final item = _selectedItems[index];
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 6.0),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (item['image'] != null && item['image'].isNotEmpty)
                      CachedNetworkImage(
                        imageUrl: item['image'].startsWith('http') ? item['image'] : '${widget.serverUrl}${item['image']}',
                        width: 50,
                        height: 50,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => const CircularProgressIndicator(),
                        errorWidget: (context, url, error) => const Icon(Icons.broken_image, size: 50),
                      )
                    else
                      const Icon(Icons.image_not_supported, size: 50, color: Colors.grey),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item['item_name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                          Text('Code: ${item['item_code']}', style: const TextStyle(color: Colors.grey)),
                          Text('Price: ₹${(item['price_list_rate'] as double).toStringAsFixed(2)}'),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(flex: 2, child: TextFormField(controller: item['quantityController'], decoration: _inputDecoration('Qty'), keyboardType: TextInputType.number, textAlign: TextAlign.center, onChanged: (v) => _updateItem(index, quantity: v))),
                              const SizedBox(width: 4),
                              Expanded(flex: 3, child: TextFormField(controller: item['discountPercentController'], decoration: _inputDecoration('Disc %'), keyboardType: const TextInputType.numberWithOptions(decimal: true), textAlign: TextAlign.center, onChanged: (v) => _updateItem(index, discountPercent: v))),
                              const SizedBox(width: 4),
                              Expanded(flex: 3, child: TextFormField(controller: item['discountAmountController'], decoration: _inputDecoration('Disc ₹'), keyboardType: const TextInputType.numberWithOptions(decimal: true), textAlign: TextAlign.center, onChanged: (v) => _updateItem(index, discountAmount: v))),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => _removeItem(index)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<String>(
                        value: item['selectedUom'],
                        decoration: _inputDecoration('UOM'),
                        isExpanded: true,
                        items: _uomList.map((uom) => DropdownMenuItem(value: uom, child: Text(uom, overflow: TextOverflow.ellipsis))).toList(),
                        onChanged: (v) => _updateItem(index, uom: v),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 3,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Text('Amt: ₹${(item['amount'] as double).toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTotalsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            _buildTotalRow('Total Quantity:', '$_cachedTotalQuantity'),
            _buildTotalRow('Subtotal (Items):', '₹${_cachedTotalAmount.toStringAsFixed(2)}'),
            if (_calculatedTaxes.isNotEmpty) const Divider(),
            ..._calculatedTaxes.map((tax) => _buildTotalRow('${tax['description']}:', '₹${(tax['tax_amount'] as double).toStringAsFixed(2)}')),
            const Divider(),
            _buildTotalRow('Grand Total:', '₹${_cachedGrandTotal.toStringAsFixed(2)}', isBold: true),
          ],
        ),
      ),
    );
  }

  Widget _buildTotalRow(String label, String value, {bool isBold = false}) {
    final style = TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal, fontSize: isBold ? 16 : 14);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label, style: style), Text(value, style: style)],
      ),
    );
  }

  Widget _buildSaveButton() {
    return ElevatedButton(
      onPressed: _isLoading ? null : _saveQuotation,
      style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 45), backgroundColor: Theme.of(context).primaryColor, foregroundColor: Colors.white, textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text('Save Quotation'),
    );
  }

  InputDecoration _inputDecoration(String? label) => InputDecoration(labelText: label, border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)), contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), filled: true, fillColor: Colors.white, isDense: true);

  BoxDecoration _boxDecoration() => BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, 2))]);
}

// Helper classes remain unchanged
class CustomerCreationDialog extends StatefulWidget {
  final String serverUrl;
  final String sid;
  const CustomerCreationDialog({Key? key, required this.serverUrl, required this.sid}) : super(key: key);
  @override
  _CustomerCreationDialogState createState() => _CustomerCreationDialogState();
}

class _CustomerCreationDialogState extends State<CustomerCreationDialog> {
  final _formKey = GlobalKey<FormState>();
  final _customerNameController = TextEditingController();
  final _mobileNoController = TextEditingController();
  final _emailController = TextEditingController();
  String _selectedTaxCategory = 'Inter State';
  final List<String> _taxCategoryOptions = ['Inter State', 'Outer State'];
  bool _isSaving = false;

  Map<String, String> _getHeaders() => {'Cookie': 'sid=${widget.sid}', 'Content-Type': 'application/json', 'Accept': 'application/json'};

  Future<void> _saveCustomer() async {
    if (!mounted || !_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      final customerData = {
        'customer_name': _customerNameController.text,
        'customer_type': 'Individual',
        'tax_category': _selectedTaxCategory,
        if (_mobileNoController.text.isNotEmpty) 'mobile_no': _mobileNoController.text,
        if (_emailController.text.isNotEmpty) 'email_id': _emailController.text,
      };
      final response = await retry(() => http.post(Uri.parse("${widget.serverUrl}/api/resource/Customer"), headers: _getHeaders(), body: json.encode({'data': customerData})), maxAttempts: 3);

      if (!mounted) return;

      if (response.statusCode == 200) {
        final newCustomerData = json.decode(response.body)['data'];
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Customer created successfully!'), backgroundColor: Colors.green));
        Navigator.pop(context, newCustomerData);
      } else {
        showApiErrorDialog(context, statusCode: response.statusCode, message: response.body);
      }
    } catch (e) {
      if (!mounted) return;
      showErrorDialog(context, 'Customer Creation Failed', 'Failed to create customer: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  void dispose() {
    _customerNameController.dispose();
    _mobileNoController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create New Customer'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(controller: _customerNameController, decoration: _inputDecoration('Customer Name *'), validator: (v) => v!.isEmpty ? 'Required' : null),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _selectedTaxCategory,
                decoration: _inputDecoration('Tax Category'),
                items: _taxCategoryOptions.map((String category) => DropdownMenuItem<String>(value: category, child: Text(category))).toList(),
                onChanged: (newValue) => setState(() => _selectedTaxCategory = newValue!),
                validator: (value) => value == null ? 'Tax category is required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(controller: _mobileNoController, decoration: _inputDecoration('Mobile No'), keyboardType: TextInputType.phone),
              const SizedBox(height: 12),
              TextFormField(controller: _emailController, decoration: _inputDecoration('Email ID'), keyboardType: TextInputType.emailAddress),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _isSaving ? null : _saveCustomer,
          child: _isSaving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save'),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(String? label) => InputDecoration(labelText: label, border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)), contentPadding: const EdgeInsets.all(10));
}

class CustomerSearchDelegate extends SearchDelegate<dynamic> {
  final List<dynamic> customers;
  CustomerSearchDelegate(this.customers);

  @override
  List<Widget>? buildActions(BuildContext context) => [IconButton(icon: const Icon(Icons.clear), onPressed: () => query = '')];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => close(context, null));

  @override
  Widget buildResults(BuildContext context) {
    final results = customers.where((c) => (c['customer_name']?.toString().toLowerCase() ?? '').contains(query.toLowerCase())).toList();
    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, index) {
        final customer = results[index];
        return ListTile(
          title: Text(customer['customer_name'] ?? 'Unknown'),
          subtitle: Text(customer['name'] ?? ''),
          onTap: () => close(context, customer),
        );
      },
    );
  }

  @override
  Widget buildSuggestions(BuildContext context) => buildResults(context);
}

class SalespersonSearchDelegate extends SearchDelegate<dynamic> {
  final List<dynamic> salespersons;
  SalespersonSearchDelegate(this.salespersons);

  @override
  List<Widget>? buildActions(BuildContext context) => [IconButton(icon: const Icon(Icons.clear), onPressed: () => query = '')];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => close(context, null));

  @override
  Widget buildResults(BuildContext context) {
    final results = salespersons.where((s) => (s['salesperson_name']?.toString().toLowerCase() ?? '').contains(query.toLowerCase())).toList();
    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, index) => ListTile(
        title: Text(results[index]['salesperson_name'] ?? 'Unknown'),
        onTap: () => close(context, results[index]),
      ),
    );
  }

  @override
  Widget buildSuggestions(BuildContext context) => buildResults(context);
}

class ItemSearchDelegate extends SearchDelegate<dynamic> {
  final List<dynamic> items;
  final String serverUrl;
  ItemSearchDelegate({required this.items, required this.serverUrl});

  @override
  List<Widget>? buildActions(BuildContext context) => [IconButton(icon: const Icon(Icons.clear), onPressed: () => query = '')];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => close(context, null));

  @override
  Widget buildResults(BuildContext context) {
    final results = items.where((item) => (item['item_name']?.toString().toLowerCase() ?? '').contains(query.toLowerCase()) || (item['item_code']?.toString().toLowerCase() ?? '').contains(query.toLowerCase())).toList();
    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, index) {
        final item = results[index];
        return ListTile(
          leading: item['image'] != null && item['image'].isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: item['image'].startsWith('http') ? item['image'] : '$serverUrl${item['image']}',
                  width: 40,
                  height: 40,
                  fit: BoxFit.cover,
                  placeholder: (c, u) => const CircularProgressIndicator(),
                  errorWidget: (c, u, e) => const Icon(Icons.error),
                )
              : const Icon(Icons.image_not_supported),
          title: Text(item['item_name'] ?? 'Unknown'),
          subtitle: Text('Code: ${item['item_code'] ?? ''}'),
          onTap: () => close(context, item),
        );
      },
    );
  }

  @override
  Widget buildSuggestions(BuildContext context) => buildResults(context);
}
