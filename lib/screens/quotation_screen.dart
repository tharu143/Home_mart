// lib/screens/quotation_screen.dart
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:barcode_scan2/barcode_scan2.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:convert';
import 'package:home_mart/error_handler.dart'; // Error handler import
import 'package:retry/retry.dart'; // Retry import for robust API calls

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
  String? _selectedSalesTaxTemplate;
  String _selectedTaxCategory = 'Inter State'; // New state for tax category

  List<Map<String, dynamic>> _customTaxes = [];

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

  List<String> _uomList = [
    'Unit',
    'Box',
    'Nos',
    'Pair',
    'Set',
    'Meter',
    'Barleycorn',
    'Calibre',
  ];

  final List<String> _taxChargeTypes = [
    'Actual',
    'On Net Total',
    'On Previous Row Amount',
    'On Previous Row Total',
    'On Item Quantity',
  ];

  final List<String> _taxCategoryOptions = [
    'Inter State',
    'Outer State',
  ]; // Tax category options

  // --- State for Custom Searchable Dropdown ---
  OverlayEntry? _overlayEntry;
  final Map<int, LayerLink> _layerLinkMap = {};
  final TextEditingController _accountSearchController =
      TextEditingController();
  List<dynamic> _filteredAccountHeads = [];
  int? _activeTaxDropdownIndex;
  // --- End State for Custom Dropdown ---

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
    for (var tax in _customTaxes) {
      tax['rateController']?.dispose();
      tax['descriptionController']?.dispose();
      tax['accountHeadController']?.dispose();
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
      setState(() {
        _quotationToController.text =
            data['quotation_to']?.toString() ?? 'Customer';
        _transactionDate =
            DateTime.tryParse(data['transaction_date']?.toString() ?? '') ??
            DateTime.now();
        _selectedTaxCategory =
            data['tax_category'] ?? 'Inter State'; // Load tax category

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
                  'conversion_factor':
                      (item['conversion_factor'] as num?)?.toDouble() ?? 0.0,
                  'price_list_rate':
                      (item['price_list_rate'] as num?)?.toDouble() ?? 0.0,
                  'discount_percent':
                      (item['discount_percentage'] as num?)?.toDouble() ?? 0.0,
                  'discount_amount':
                      (item['discount_amount'] as num?)?.toDouble() ?? 0.0,
                  'amount': _calculateItemAmount(item),
                  'image': item['image']?.toString(),
                  'barcode': _parseBarcodeFromItem(item),
                  'taxes': item['taxes'] ?? fullItemData['taxes'] ?? [],
                  'quantityController': TextEditingController(
                    text: (item['qty'] ?? 1).toString(),
                  ),
                  'discountPercentController': TextEditingController(
                    text: ((item['discount_percentage'] ?? 0.0) as num)
                        .toDouble()
                        .toStringAsFixed(2),
                  ),
                  'discountAmountController': TextEditingController(
                    text: ((item['discount_amount'] ?? 0.0) as num)
                        .toDouble()
                        .toStringAsFixed(2),
                  ),
                  'selectedUom': item['uom']?.toString() ?? 'Nos',
                };
              }) ??
              [],
        );

        final customerNameFromData =
            data['customer']?.toString() ?? data['customer_name']?.toString();
        if (customerNameFromData != null) {
          _selectedCustomer = _customersList.firstWhere(
            (customer) => customer['name'] == customerNameFromData,
            orElse: () => {
              'name': customerNameFromData,
              'customer_name': customerNameFromData,
              'tax_category': 'Inter State',
            },
          );
          _selectedTaxCategory =
              _selectedCustomer?['tax_category'] ?? 'Inter State';
        }

        _selectedSalesperson = data['sales_person'] != null
            ? _salespersonsList.firstWhere(
                (sp) => sp['salesperson_name'] == data['sales_person'],
                orElse: () => {'salesperson_name': data['sales_person']},
              )
            : null;

        _selectedSalesTaxTemplate = data['taxes_and_charges']?.toString();

        if (data['taxes'] != null && (data['taxes'] as List).isNotEmpty) {
          _customTaxes = List<Map<String, dynamic>>.from(
            (data['taxes'] as List<dynamic>).map((tax) {
              final accountHeadName = tax['account_head']?.toString();
              final account = _accountHeads.firstWhere(
                (h) => h['name'] == accountHeadName,
                orElse: () => null,
              );
              final displayName =
                  account?['account_name'] ?? accountHeadName ?? '';

              return {
                'charge_type': tax['charge_type']?.toString() ?? 'On Net Total',
                'account_head': accountHeadName,
                'description': tax['description']?.toString() ?? '',
                'rate': (tax['rate'] as num?)?.toDouble() ?? 0.0,
                'rateController': TextEditingController(
                  text: (tax['rate']?.toDouble() ?? 0.0).toStringAsFixed(2),
                ),
                'descriptionController': TextEditingController(
                  text: tax['description']?.toString() ?? '',
                ),
                'accountHeadController': TextEditingController(
                  text: displayName,
                ),
              };
            }),
          );
        }
      });
    }
    _updateTotals();
  }

  String _parseBarcodeFromItem(dynamic item) {
    String barcodeValue = item['barcode']?.toString() ?? '';
    if (barcodeValue.startsWith('<svg') &&
        barcodeValue.contains('data-barcode-value=')) {
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

  Future<dynamic> _fetchData(
    String endpoint, {
    bool isCustomMethod = true,
  }) async {
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
        showApiErrorDialog(
          context,
          statusCode: response.statusCode,
          message: response.body,
        );
        return null;
      }
    } catch (e) {
      showErrorDialog(
        context,
        'Network Error',
        'Failed to fetch data from $endpoint: $e',
      );
      return null;
    }
  }

  Future<void> _fetchItems() async {
    final data = await _fetchData("custom_scripts.API.qtn.get_item_details");
    if (data != null && data['message'] != null) {
      if (mounted)
        setState(() => _itemsList = (data['message'] as List<dynamic>?) ?? []);
    }
  }

  Future<void> _fetchCustomers() async {
    final data = await _fetchData("custom_scripts.API.qtn.get_customers");
    if (data != null && data['message'] != null) {
      if (mounted)
        setState(
          () => _customersList = (data['message'] as List<dynamic>?) ?? [],
        );
    }
  }

  Future<void> _fetchSalespersons() async {
    final data = await _fetchData("custom_scripts.API.qtn.get_salesperson");
    if (data != null && data['message'] != null) {
      if (mounted) {
        setState(() {
          _salespersonsList =
              (data['message'] as List<dynamic>?)
                  ?.map(
                    (item) => ({
                      'salesperson_name':
                          item['sales_person_name']?.toString() ?? '',
                    }),
                  )
                  .toList() ??
              [];
        });
      }
    }
  }

  Future<void> _fetchSalesTaxesTemplates() async {
    final data = await _fetchData(
      "custom_scripts.API.qtn.get_all_sales_taxes_templates1",
    );
    if (data != null && data['message'] != null) {
      if (mounted)
        setState(
          () => _salesTaxTemplates = (data['message'] as List<dynamic>?) ?? [],
        );
    }
  }

  Future<void> _fetchAccountHeads() async {
    final data = await _fetchData("custom_scripts.API.qtn.get_accounts");
    if (data != null && data['message'] != null) {
      if (mounted)
        setState(
          () => _accountHeads = (data['message'] as List<dynamic>?) ?? [],
        );
    }
  }

  Future<void> _scanBarcode() async {
    if (await Permission.camera.request().isGranted) {
      try {
        final result = await BarcodeScanner.scan();
        if (result.type == ResultType.Barcode) {
          final barcode = result.rawContent;
          final item = _itemsList.firstWhere(
            (item) => _parseBarcodeFromItem(item) == barcode,
            orElse: () => null,
          );
          if (item != null) {
            _addItemToResult(item);
          } else {
            showErrorDialog(
              context,
              'Item Not Found',
              'No item found for barcode: $barcode',
            );
          }
        }
      } catch (e) {
        showErrorDialog(
          context,
          'Barcode Scan Error',
          'Failed to scan barcode: $e',
        );
      }
    } else {
      showErrorDialog(context, 'Permission Denied', 'Camera permission denied');
    }
  }

  void _addItemToResult(dynamic item) {
    setState(() {
      _selectedItems.add({
        'item_name': item['item_name'] ?? 'Unknown',
        'item_code': item['item_code'] ?? '',
        'quantity': 1,
        'uom': item['uom'] ?? 'Nos',
        'conversion_factor':
            (item['conversion_factor'] as num?)?.toDouble() ?? 0.0,
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
        'selectedUom': item['uom'] ?? 'Nos',
      });
      _updateTotals();
    });
  }

  double _calculateItemAmount(Map<String, dynamic> item) {
    final price = (item['price_list_rate'] as num?)?.toDouble() ?? 0.0;
    final qty = (item['quantity'] ?? item['qty'] as num?)?.toInt() ?? 1;
    final discount = (item['discount_amount'] as num?)?.toDouble() ?? 0.0;
    return (price * qty - discount).clamp(0.0, double.infinity);
  }

  void _updateItem(
    int index, {
    String? quantity,
    String? discountPercent,
    String? discountAmount,
    String? uom,
  }) {
    setState(() {
      final item = _selectedItems[index];
      if (quantity != null) {
        final qty = int.tryParse(quantity) ?? 1;
        if (qty <= 0) {
          _removeItem(index);
          return;
        }
        item['quantity'] = qty;
      }

      final price = item['price_list_rate'] as double;
      final currentQty = item['quantity'] as int;

      if (discountPercent != null) {
        final percent = double.tryParse(discountPercent) ?? 0.0;
        item['discount_percent'] = percent.clamp(0, 100);
        item['discount_amount'] =
            (price * currentQty * item['discount_percent'] / 100);
      } else if (discountAmount != null) {
        final amount = double.tryParse(discountAmount) ?? 0.0;
        final subtotal = price * currentQty;
        item['discount_amount'] = amount.clamp(0, subtotal);
        item['discount_percent'] = subtotal > 0
            ? (item['discount_amount'] / subtotal * 100).clamp(0, 100)
            : 0.0;
      }

      if (uom != null) {
        item['selectedUom'] = uom;
      }

      item['quantityController'].text = item['quantity'].toString();
      item['discountPercentController'].text = item['discount_percent']
          .toStringAsFixed(2);
      item['discountAmountController'].text = item['discount_amount']
          .toStringAsFixed(2);
      item['amount'] = _calculateItemAmount(item);

      _updateTotals();
    });
  }

  void _removeItem(int index) {
    setState(() {
      _selectedItems[index]['quantityController']?.dispose();
      _selectedItems[index]['discountPercentController']?.dispose();
      _selectedItems[index]['discountAmountController']?.dispose();
      _selectedItems.removeAt(index);
      _updateTotals();
    });
  }

  void _addCustomTaxRow() {
    setState(() {
      _customTaxes.add({
        'charge_type': 'On Net Total',
        'account_head': null,
        'description': '',
        'rate': 0.0,
        'rateController': TextEditingController(text: '0.00'),
        'descriptionController': TextEditingController(),
        'accountHeadController': TextEditingController(),
      });
      _layerLinkMap[_customTaxes.length - 1] = LayerLink();
      _calculateTaxes();
    });
  }

  void _updateCustomTaxRow(
    int index, {
    String? type,
    String? accountHead,
    String? description,
    String? rate,
  }) {
    setState(() {
      final tax = _customTaxes[index];
      if (type != null) tax['charge_type'] = type;
      if (accountHead != null) {
        tax['account_head'] = accountHead;
        final selectedAccount = _accountHeads.firstWhere(
          (acc) => acc['name'] == accountHead,
          orElse: () => null,
        );
        if (selectedAccount != null) {
          tax['descriptionController'].text =
              selectedAccount['account_name'] ?? accountHead;
          tax['description'] = selectedAccount['account_name'] ?? accountHead;
          tax['accountHeadController'].text =
              selectedAccount['account_name'] ?? accountHead;
        }
      }
      if (description != null) tax['description'] = description;
      if (rate != null) tax['rate'] = double.tryParse(rate) ?? 0.0;

      _calculateTaxes();
    });
  }

  void _removeCustomTaxRow(int index) {
    _removeOverlay();
    setState(() {
      _customTaxes[index]['rateController']?.dispose();
      _customTaxes[index]['descriptionController']?.dispose();
      _customTaxes[index]['accountHeadController']?.dispose();
      _customTaxes.removeAt(index);
      _layerLinkMap.remove(index);
      _calculateTaxes();
    });
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    _activeTaxDropdownIndex = null;
  }

  void _showAccountHeadOverlay(BuildContext context, int taxIndex) {
    _removeOverlay();

    final renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;
    if (!_layerLinkMap.containsKey(taxIndex)) {
      _layerLinkMap[taxIndex] = LayerLink();
    }
    final layerLink = _layerLinkMap[taxIndex]!;

    setState(() {
      _activeTaxDropdownIndex = taxIndex;
      _filteredAccountHeads = _accountHeads;
      _accountSearchController.clear();
    });

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        width: size.width + 40,
        child: CompositedTransformFollower(
          link: layerLink,
          showWhenUnlinked: false,
          offset: Offset(0.0, size.height),
          child: Material(
            elevation: 4.0,
            child: SizedBox(
              height: 250,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: TextField(
                      controller: _accountSearchController,
                      autofocus: true,
                      decoration: _inputDecoration('Search Account...'),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      itemCount: _filteredAccountHeads.length,
                      itemBuilder: (context, index) {
                        final account = _filteredAccountHeads[index];
                        final accountName =
                            account['account_name'] ?? account['name'];
                        return ListTile(
                          title: Text(accountName),
                          onTap: () {
                            _updateCustomTaxRow(
                              taxIndex,
                              accountHead: account['name'],
                            );
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
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _filterAccountHeads(String query) {
    if (_overlayEntry == null) return;

    List<dynamic> newFilteredList = [];
    if (query.isEmpty) {
      newFilteredList = _accountHeads;
    } else {
      newFilteredList = _accountHeads.where((account) {
        final accountName = (account['account_name'] ?? account['name'])
            .toString()
            .toLowerCase();
        return accountName.contains(query.toLowerCase());
      }).toList();
    }

    if (mounted) {
      setState(() {
        _filteredAccountHeads = newFilteredList;
      });
    }
    _overlayEntry?.markNeedsBuild();
  }

  void _updateTotals() {
    setState(() {
      _cachedTotalQuantity = _selectedItems.fold(
        0,
        (sum, item) => sum + (item['quantity'] as int),
      );
      _cachedTotalAmount = _selectedItems.fold(
        0.0,
        (sum, item) => sum + (item['amount'] as double),
      );
      _calculateTaxes();
    });
  }

  double _calculateTaxAmount(
    String chargeType,
    double rate,
    double netTotal,
    int totalQuantity,
  ) {
    switch (chargeType) {
      case 'On Net Total':
        return (netTotal * rate / 100);
      case 'Actual':
        return rate;
      case 'On Item Quantity':
        return (totalQuantity * rate).toDouble();
      case 'On Previous Row Amount':
      case 'On Previous Row Total':
        return (netTotal * rate / 100);
      default:
        return 0.0;
    }
  }

  void _calculateTaxes() {
    List<Map<String, dynamic>> tempCalculatedTaxes = [];
    final double netTotal = _cachedTotalAmount;
    Set<String> processedAccountHeads = {};

    void processTaxComponent(
      Map<String, dynamic> taxComponent,
      bool isCustom, {
      TextEditingController? descCtrl,
      TextEditingController? rateCtrl,
    }) {
      final String accountHead = taxComponent['account_head']?.toString() ?? '';
      if (accountHead.isEmpty || processedAccountHeads.contains(accountHead))
        return;

      final String chargeType = taxComponent['charge_type'] ?? 'On Net Total';
      final double rate = isCustom
          ? (double.tryParse(rateCtrl!.text) ?? 0.0)
          : ((taxComponent['rate'] as num?)?.toDouble() ?? 0.0);
      final String description = isCustom
          ? descCtrl!.text
          : (taxComponent['description'] ??
                taxComponent['account_head'] ??
                'Tax');

      double taxAmountForComponent = _calculateTaxAmount(
        chargeType,
        rate,
        netTotal,
        _cachedTotalQuantity,
      );

      tempCalculatedTaxes.add({
        'description': description,
        'charge_type': chargeType,
        'account_head': accountHead,
        'tax_amount': taxAmountForComponent,
        'rate': rate,
        'isCustom': isCustom,
      });
      processedAccountHeads.add(accountHead);
    }

    for (var customTax in _customTaxes) {
      processTaxComponent(
        customTax,
        true,
        descCtrl: customTax['descriptionController'],
        rateCtrl: customTax['rateController'],
      );
    }

    // UPDATED LOGIC: Filter item taxes based on selected tax category
    for (var item in _selectedItems) {
      final List<dynamic> itemTaxes = item['taxes'] ?? [];
      for (var itemTaxInfo in itemTaxes) {
        if (itemTaxInfo['tax_category'] == _selectedTaxCategory) {
          final String? templateName = itemTaxInfo['item_tax_template'];
          if (templateName == null) continue;

          final selectedTemplate = _salesTaxTemplates.firstWhere(
            (t) => t['template_name'] == templateName,
            orElse: () => null,
          );

          if (selectedTemplate != null && selectedTemplate['taxes'] != null) {
            for (var taxComponent in selectedTemplate['taxes']) {
              processTaxComponent(taxComponent, false);
            }
          }
        }
      }
    }

    if (_selectedSalesTaxTemplate != null) {
      final selectedTemplate = _salesTaxTemplates.firstWhere(
        (t) => t['template_name'] == _selectedSalesTaxTemplate,
        orElse: () => null,
      );

      if (selectedTemplate != null && selectedTemplate['taxes'] != null) {
        for (var taxComponent in selectedTemplate['taxes']) {
          processTaxComponent(taxComponent, false);
        }
      }
    }

    double totalTaxAmount = tempCalculatedTaxes.fold(
      0.0,
      (sum, tax) => sum + (tax['tax_amount']?.toDouble() ?? 0.0),
    );

    if (mounted) {
      setState(() {
        _calculatedTaxes = tempCalculatedTaxes;
        _cachedGrandTotal = _cachedTotalAmount + totalTaxAmount;
      });
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _transactionDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      if (mounted) setState(() => _transactionDate = picked);
    }
  }

  Future<void> _saveQuotation() async {
    _removeOverlay();
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCustomer == null) {
      showErrorDialog(context, 'Validation Error', 'Please select a customer.');
      return;
    }
    if (_selectedSalesperson == null) {
      showErrorDialog(
        context,
        'Validation Error',
        'Please select a salesperson.',
      );
      return;
    }
    if (_selectedItems.isEmpty) {
      showErrorDialog(
        context,
        'Validation Error',
        'Please add at least one item.',
      );
      return;
    }

    setState(() => _isLoading = true);

    final itemsToSave = _selectedItems
        .map(
          (item) => {
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
            'cost_center': 'Main - NG', // Hardcoded Cost Center
          },
        )
        .toList();

    final taxesToSave = _calculatedTaxes
        .map(
          (tax) => {
            'account_head': tax['account_head'],
            'charge_type': tax['charge_type'],
            'description': tax['description'],
            'rate': tax['rate'],
          },
        )
        .toList();

    final Map<String, dynamic> quotationData = {
      'quotation_to': _quotationToController.text.isEmpty
          ? 'Customer'
          : _quotationToController.text,
      'customer': _selectedCustomer['name']?.toString() ?? '',
      'party_name': _selectedCustomer['customer_name']?.toString() ?? '',
      'sales_person':
          _selectedSalesperson['salesperson_name']?.toString() ?? '',
      'transaction_date': DateFormat('yyyy-MM-dd').format(_transactionDate),
      'status': widget.initialData?['status']?.toString() ?? 'Draft',
      'items': itemsToSave,
      'taxes': taxesToSave,
      'tax_category': _selectedTaxCategory, // Save the selected tax category
      if (_selectedSalesTaxTemplate != null)
        'taxes_and_charges': _selectedSalesTaxTemplate,
      'cost_center': 'Main - NG', // Hardcoded Cost Center
      'naming_series': _namingSeries,
      'selling_price_list': _sellingPriceList,
      'currency': _currency,
      if (widget.initialData != null && widget.initialData!['name'] != null)
        'name': widget.initialData!['name'],
    };

    try {
      final http.Response response;
      if (widget.initialData == null || widget.initialData!['name'] == null) {
        response = await retry(
          () => http.post(
            Uri.parse("${widget.serverUrl}/api/resource/Quotation"),
            headers: _getHeaders(),
            body: json.encode({"data": quotationData}),
          ),
        );
      } else {
        response = await retry(
          () => http.put(
            Uri.parse(
              "${widget.serverUrl}/api/resource/Quotation/${widget.initialData!['name']}",
            ),
            headers: _getHeaders(),
            body: json.encode({"data": quotationData}),
          ),
        );
      }

      if (response.statusCode == 200 || response.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.initialData == null
                  ? 'Quotation created successfully!'
                  : 'Quotation updated successfully!',
            ),
          ),
        );
        Navigator.pop(context, true);
      } else {
        showApiErrorDialog(
          context,
          statusCode: response.statusCode,
          message: response.body,
        );
      }
    } catch (e) {
      showErrorDialog(
        context,
        'Operation Failed',
        'Failed to save quotation: $e',
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- WIDGET BUILDERS ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE0F7FA),
      appBar: AppBar(
        title: Text(
          widget.initialData == null ? 'Create Quotation' : 'Edit Quotation',
          style: const TextStyle(fontFamily: 'Dubai', color: Colors.white),
        ),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
      ),
      body: GestureDetector(
        onTap: _removeOverlay,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(16.0),
                  children: [
                    _buildSectionHeader(context, 'General Information'),
                    _buildDateField(context),
                    const SizedBox(height: 10),
                    _buildSectionHeader(context, 'Parties'),
                    _buildCustomerSelector(),
                    const SizedBox(height: 10),
                    _buildTaxCategoryDropdown(),
                    const SizedBox(height: 10),
                    _buildSalespersonSelector(),
                    const SizedBox(height: 10),
                    _buildSectionHeader(context, 'Item Details'),
                    _buildItemAdder(),
                    if (_selectedItems.isNotEmpty) _buildItemsList(),
                    const SizedBox(height: 10),
                    _buildSectionHeader(context, 'Accounting & Taxes'),
                    _buildSalesTaxTemplateDropdown(),
                    const SizedBox(height: 10),
                    _buildTaxesSection(),
                    const SizedBox(height: 10),
                    _buildTotalsCard(),
                    const SizedBox(height: 20),
                    _buildSaveButton(),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          color: Theme.of(context).primaryColor,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildDateField(BuildContext context) {
    return GestureDetector(
      onTap: () => _selectDate(context),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: _boxDecoration(),
        child: Row(
          children: [
            const Icon(Icons.calendar_today, color: Color(0xFF005BAC)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(DateFormat('yyyy-MM-dd').format(_transactionDate)),
            ),
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
              final selected = await showSearch(
                context: context,
                delegate: CustomerSearchDelegate(_customersList),
              );
              if (selected != null) {
                setState(() {
                  _selectedCustomer = selected;
                  _selectedTaxCategory =
                      selected['tax_category'] ?? 'Inter State';
                  _calculateTaxes();
                });
              }
            },
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: _boxDecoration(),
              child: Row(
                children: [
                  const Icon(Icons.person, color: Color(0xFF005BAC)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _selectedCustomer?['customer_name'] ?? 'Select Customer',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Icon(Icons.arrow_drop_down, color: Colors.grey),
                ],
              ),
            ),
          ),
        ),
        IconButton(
          icon: const Icon(
            Icons.add_circle_outline,
            color: Color(0xFF005BAC),
            size: 30,
          ),
          onPressed: () async {
            _removeOverlay();
            final newCustomer = await showDialog<Map<String, dynamic>>(
              context: context,
              builder: (context) => CustomerCreationDialog(
                serverUrl: widget.serverUrl,
                sid: widget.sid,
              ),
            );
            if (newCustomer != null) {
              await _fetchCustomers();
              setState(() {
                _selectedCustomer = _customersList.firstWhere(
                  (c) => c['name'] == newCustomer['name'],
                  orElse: () => newCustomer,
                );
                _selectedTaxCategory =
                    newCustomer['tax_category'] ?? 'Inter State';
                _calculateTaxes();
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
      items: _taxCategoryOptions.map((String category) {
        return DropdownMenuItem<String>(value: category, child: Text(category));
      }).toList(),
      onChanged: (newValue) {
        setState(() {
          _selectedTaxCategory = newValue!;
          _calculateTaxes();
        });
      },
      validator: (value) => value == null ? 'Tax category is required' : null,
    );
  }

  Widget _buildSalespersonSelector() {
    return GestureDetector(
      onTap: () async {
        _removeOverlay();
        final selected = await showSearch(
          context: context,
          delegate: SalespersonSearchDelegate(_salespersonsList),
        );
        if (selected != null) setState(() => _selectedSalesperson = selected);
      },
      child: Container(
        padding: const EdgeInsets.all(12.0),
        decoration: _boxDecoration(),
        child: Row(
          children: [
            const Icon(Icons.people_alt, color: Color(0xFF005BAC)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _selectedSalesperson?['salesperson_name'] ??
                    'Select Salesperson',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.arrow_drop_down, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _buildSalesTaxTemplateDropdown() {
    return DropdownButtonFormField<String>(
      value: _selectedSalesTaxTemplate,
      decoration: _inputDecoration('Sales Tax Template (Optional)'),
      isExpanded: true,
      items: [
        const DropdownMenuItem<String>(
          value: null,
          child: Text('None', style: TextStyle(color: Colors.grey)),
        ),
        ..._salesTaxTemplates.map(
          (template) => DropdownMenuItem<String>(
            value: template['template_name'],
            child: Text(
              template['title'] ?? template['template_name'],
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
      onChanged: (value) {
        _removeOverlay();
        setState(() => _selectedSalesTaxTemplate = value);
        _calculateTaxes();
      },
    );
  }

  Widget _buildTaxesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCustomTaxesTable(),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: ElevatedButton.icon(
            onPressed: _addCustomTaxRow,
            icon: const Icon(Icons.add),
            label: const Text('Add Custom Tax Row'),
          ),
        ),
      ],
    );
  }

  Widget _buildCustomTaxesTable() {
    if (_customTaxes.isEmpty) {
      return const SizedBox.shrink();
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        columnWidths: const {
          0: FixedColumnWidth(150), // Type
          1: FixedColumnWidth(200), // Account Head
          2: FixedColumnWidth(150), // Description
          3: FixedColumnWidth(100), // Rate
          4: FixedColumnWidth(50), // Action
        },
        border: TableBorder.all(
          color: Colors.grey.shade300,
          borderRadius: BorderRadius.circular(8),
        ),
        children: [
          _buildCustomTaxTableHeader(),
          ..._customTaxes.asMap().entries.map((entry) {
            if (!_layerLinkMap.containsKey(entry.key)) {
              _layerLinkMap[entry.key] = LayerLink();
            }
            return _buildCustomTaxTableRow(entry.key, entry.value);
          }).toList(),
        ],
      ),
    );
  }

  TableRow _buildCustomTaxTableHeader() {
    const style = TextStyle(fontWeight: FontWeight.bold, fontSize: 12);
    return const TableRow(
      decoration: BoxDecoration(
        color: Color(0xFFE0F7FA),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(8),
          topRight: Radius.circular(8),
        ),
      ),
      children: [
        Padding(
          padding: EdgeInsets.all(8.0),
          child: Text('Type', style: style, textAlign: TextAlign.center),
        ),
        Padding(
          padding: EdgeInsets.all(8.0),
          child: Text(
            'Account Head *',
            style: style,
            textAlign: TextAlign.center,
          ),
        ),
        Padding(
          padding: EdgeInsets.all(8.0),
          child: Text('Description', style: style, textAlign: TextAlign.center),
        ),
        Padding(
          padding: EdgeInsets.all(8.0),
          child: Text('Rate', style: style, textAlign: TextAlign.center),
        ),
        Padding(
          padding: EdgeInsets.all(8.0),
          child: Text(' ', style: style),
        ),
      ],
    );
  }

  TableRow _buildCustomTaxTableRow(int index, Map<String, dynamic> tax) {
    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.all(4.0),
          child: DropdownButtonFormField<String>(
            value: tax['charge_type'],
            decoration: _inputDecoration(null),
            isExpanded: true,
            items: _taxChargeTypes
                .map(
                  (t) => DropdownMenuItem(
                    value: t,
                    child: Text(
                      t,
                      style: const TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: (v) => _updateCustomTaxRow(index, type: v),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(4.0),
          child: CompositedTransformTarget(
            link: _layerLinkMap[index]!,
            child: Builder(
              builder: (context) {
                return TextFormField(
                  controller: tax['accountHeadController'],
                  readOnly: true,
                  decoration: _inputDecoration(null),
                  onTap: () => _showAccountHeadOverlay(context, index),
                  validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                );
              },
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(4.0),
          child: TextFormField(
            controller: tax['descriptionController'],
            decoration: _inputDecoration(null),
            onChanged: (v) => _updateCustomTaxRow(index, description: v),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(4.0),
          child: TextFormField(
            controller: tax['rateController'],
            decoration: _inputDecoration(null),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.center,
            onChanged: (v) => _updateCustomTaxRow(index, rate: v),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.red),
          onPressed: () => _removeCustomTaxRow(index),
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
              final selected = await showSearch(
                context: context,
                delegate: ItemSearchDelegate(
                  items: _itemsList,
                  serverUrl: widget.serverUrl,
                ),
              );
              if (selected != null) _addItemToResult(selected);
            },
            child: Container(
              padding: const EdgeInsets.all(12.0),
              decoration: _boxDecoration(),
              child: const Row(
                children: [
                  Icon(Icons.add_shopping_cart, color: Color(0xFF005BAC)),
                  SizedBox(width: 8),
                  Expanded(child: Text('Add Item')),
                ],
              ),
            ),
          ),
        ),
        IconButton(
          icon: const Icon(
            Icons.qr_code_scanner,
            color: Color(0xFF005BAC),
            size: 30,
          ),
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
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (item['image'] != null && item['image'].isNotEmpty)
                  CachedNetworkImage(
                    imageUrl: item['image'].startsWith('http')
                        ? item['image']
                        : '${widget.serverUrl}${item['image']}',
                    width: 60,
                    height: 60,
                    fit: BoxFit.cover,
                    placeholder: (context, url) =>
                        const CircularProgressIndicator(),
                    errorWidget: (context, url, error) =>
                        const Icon(Icons.broken_image, size: 60),
                  )
                else
                  const Icon(
                    Icons.image_not_supported,
                    size: 60,
                    color: Colors.grey,
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item['item_name'],
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Code: ${item['item_code']}',
                        style: const TextStyle(color: Colors.grey),
                      ),
                      Text(
                        'Price: ₹${(item['price_list_rate'] as double).toStringAsFixed(2)}',
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: item['quantityController'],
                              decoration: _inputDecoration('Qty'),
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              onChanged: (v) => _updateItem(index, quantity: v),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: TextFormField(
                              controller: item['discountPercentController'],
                              decoration: _inputDecoration('Disc %'),
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              onChanged: (v) =>
                                  _updateItem(index, discountPercent: v),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: TextFormField(
                              controller: item['discountAmountController'],
                              decoration: _inputDecoration('Disc ₹'),
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              onChanged: (v) =>
                                  _updateItem(index, discountAmount: v),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Amount: ₹${(item['amount'] as double).toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => _removeItem(index),
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
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildTotalRow('Total Quantity:', '$_cachedTotalQuantity'),
            _buildTotalRow(
              'Subtotal (Items):',
              '₹${_cachedTotalAmount.toStringAsFixed(2)}',
            ),
            if (_calculatedTaxes.isNotEmpty) const Divider(),
            ..._calculatedTaxes.map(
              (tax) => _buildTotalRow(
                '${tax['description']}:',
                '₹${(tax['tax_amount'] as double).toStringAsFixed(2)}',
              ),
            ),
            const Divider(),
            _buildTotalRow(
              'Grand Total:',
              '₹${_cachedGrandTotal.toStringAsFixed(2)}',
              isBold: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTotalRow(String label, String value, {bool isBold = false}) {
    final style = TextStyle(
      fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
      fontSize: isBold ? 16 : 14,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(value, style: style),
        ],
      ),
    );
  }

  Widget _buildSaveButton() {
    return ElevatedButton(
      onPressed: _isLoading ? null : _saveQuotation,
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(double.infinity, 50),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
      ),
      child: _isLoading
          ? const CircularProgressIndicator(color: Colors.white)
          : const Text('Save Quotation'),
    );
  }

  InputDecoration _inputDecoration(String? label) => InputDecoration(
    labelText: label,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    filled: true,
    fillColor: Colors.white,
  );

  BoxDecoration _boxDecoration() => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(8),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(0.1),
        blurRadius: 4,
        offset: const Offset(0, 2),
      ),
    ],
  );
}

// --- DIALOGS AND SEARCH DELEGATES ---

class CustomerCreationDialog extends StatefulWidget {
  final String serverUrl;
  final String sid;
  const CustomerCreationDialog({
    Key? key,
    required this.serverUrl,
    required this.sid,
  }) : super(key: key);
  @override
  State<CustomerCreationDialog> createState() => _CustomerCreationDialogState();
}

class _CustomerCreationDialogState extends State<CustomerCreationDialog> {
  final _formKey = GlobalKey<FormState>();
  final _customerNameController = TextEditingController();
  final _mobileNoController = TextEditingController();
  final _emailController = TextEditingController();
  String _selectedTaxCategory = 'Inter State';
  final List<String> _taxCategoryOptions = ['Inter State', 'Outer State'];
  bool _isSaving = false;

  Map<String, String> _getHeaders() => {
    'Cookie': 'sid=${widget.sid}',
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  Future<void> _saveCustomer() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      final customerData = {
        'customer_name': _customerNameController.text,
        'customer_type': 'Individual',
        'tax_category': _selectedTaxCategory,
        if (_mobileNoController.text.isNotEmpty)
          'mobile_no': _mobileNoController.text,
        if (_emailController.text.isNotEmpty) 'email_id': _emailController.text,
      };
      final response = await retry(
        () => http.post(
          Uri.parse("${widget.serverUrl}/api/resource/Customer"),
          headers: _getHeaders(),
          body: json.encode({'data': customerData}),
        ),
      );
      if (response.statusCode == 200) {
        final newCustomerData = json.decode(response.body)['data'];
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Customer created successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, newCustomerData);
      } else {
        showApiErrorDialog(
          context,
          statusCode: response.statusCode,
          message: response.body,
        );
      }
    } catch (e) {
      showErrorDialog(
        context,
        'Customer Creation Failed',
        'Failed to create customer: $e',
      );
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
              TextFormField(
                controller: _customerNameController,
                decoration: _inputDecoration('Customer Name *'),
                validator: (v) => v!.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _selectedTaxCategory,
                decoration: _inputDecoration('Tax Category'),
                items: _taxCategoryOptions.map((String category) {
                  return DropdownMenuItem<String>(
                    value: category,
                    child: Text(category),
                  );
                }).toList(),
                onChanged: (newValue) {
                  setState(() {
                    _selectedTaxCategory = newValue!;
                  });
                },
                validator: (value) =>
                    value == null ? 'Tax category is required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _mobileNoController,
                decoration: _inputDecoration('Mobile No'),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _emailController,
                decoration: _inputDecoration('Email ID'),
                keyboardType: TextInputType.emailAddress,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : _saveCustomer,
          child: _isSaving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(String? label) => InputDecoration(
    labelText: label,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
    contentPadding: const EdgeInsets.all(12),
  );
}

class CustomerSearchDelegate extends SearchDelegate<dynamic> {
  final List<dynamic> customers;
  CustomerSearchDelegate(this.customers);

  @override
  List<Widget>? buildActions(BuildContext context) => [
    IconButton(icon: const Icon(Icons.clear), onPressed: () => query = ''),
  ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
    icon: const Icon(Icons.arrow_back),
    onPressed: () => close(context, null),
  );

  @override
  Widget buildResults(BuildContext context) {
    final results = customers
        .where(
          (c) => (c['customer_name']?.toString().toLowerCase() ?? '').contains(
            query.toLowerCase(),
          ),
        )
        .toList();
    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, index) {
        final customer = results[index];
        return ListTile(
          title: Text(customer['customer_name']),
          subtitle: Text(customer['name']),
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
  List<Widget>? buildActions(BuildContext context) => [
    IconButton(icon: const Icon(Icons.clear), onPressed: () => query = ''),
  ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
    icon: const Icon(Icons.arrow_back),
    onPressed: () => close(context, null),
  );

  @override
  Widget buildResults(BuildContext context) {
    final results = salespersons
        .where(
          (s) => (s['salesperson_name']?.toString().toLowerCase() ?? '')
              .contains(query.toLowerCase()),
        )
        .toList();
    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, index) => ListTile(
        title: Text(results[index]['salesperson_name']),
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
  List<Widget>? buildActions(BuildContext context) => [
    IconButton(icon: const Icon(Icons.clear), onPressed: () => query = ''),
  ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
    icon: const Icon(Icons.arrow_back),
    onPressed: () => close(context, null),
  );

  @override
  Widget buildResults(BuildContext context) {
    final results = items
        .where(
          (item) =>
              (item['item_name']?.toString().toLowerCase() ?? '').contains(
                query.toLowerCase(),
              ) ||
              (item['item_code']?.toString().toLowerCase() ?? '').contains(
                query.toLowerCase(),
              ),
        )
        .toList();
    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, index) {
        final item = results[index];
        return ListTile(
          leading: item['image'] != null && item['image'].isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: item['image'].startsWith('http')
                      ? item['image']
                      : '$serverUrl${item['image']}',
                  width: 40,
                  height: 40,
                  fit: BoxFit.cover,
                  placeholder: (c, u) => const CircularProgressIndicator(),
                  errorWidget: (c, u, e) => const Icon(Icons.error),
                )
              : const Icon(Icons.image_not_supported),
          title: Text(item['item_name']),
          subtitle: Text('Code: ${item['item_code']}'),
          onTap: () => close(context, item),
        );
      },
    );
  }

  @override
  Widget buildSuggestions(BuildContext context) => buildResults(context);
}
