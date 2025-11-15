import 'dart:convert';
import 'dart:typed_data'; // For Uint8List
import 'package:barcode_scan2/barcode_scan2.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart'; // For PdfColor, PdfPageFormat
import 'package:pdf/widgets.dart' as pw;
import 'package:permission_handler/permission_handler.dart';
import 'package:printing/printing.dart';
import 'package:retry/retry.dart';
import 'package:home_mart/error_handler.dart'; // Assumed to contain error dialog functions

class QuotationDetailScreen extends StatefulWidget {
  final String serverUrl;
  final String sid; // Added SID for API calls
  const QuotationDetailScreen({
    super.key,
    required this.serverUrl,
    required this.sid, // Added SID
  });
  @override
  State<QuotationDetailScreen> createState() => _QuotationDetailScreenState();
}

class _QuotationDetailScreenState extends State<QuotationDetailScreen> {
  final _formKey = GlobalKey<FormState>();
  // State for toggling between read-only and edit modes
  bool _isEditing = false;
  // State variables from Quotation Create Screen
  Map<String, dynamic>? _initialData;
  List<dynamic> _itemsList = [];
  List<dynamic> _customersList = [];
  List<dynamic> _salespersonsList = [];
  List<Map<String, dynamic>> _selectedItems = [];
  List<dynamic> _salesTaxTemplates = [];
  List<dynamic> _accountHeads = [];
  dynamic _selectedCustomer;
  dynamic _selectedSalesperson;
  String _selectedTaxCategory = 'Inter State';
  List<Map<String, dynamic>> _customTaxes = [];
  bool _isLoading = true;
  bool _isEditDataReady = false; // Tracks if background data for editing is loaded
  final _quotationToController = TextEditingController(text: 'Customer');
  DateTime _transactionDate = DateTime.now();
  double _cachedTotalAmount = 0.0;
  double _cachedGrandTotal = 0.0;
  int _cachedTotalQuantity = 0;
  double _cachedNetTotal = 0.0; // ADDED for new calculation logic
  List<Map<String, dynamic>> _calculatedTaxes = [];
  final String _namingSeries = 'SAL-QTN-.YYYY';
  final String _sellingPriceList = 'Standard Selling';
  final String _currency = 'INR';
  final Set<String> _manuallyRemovedTaxes = {};
  final List<String> _uomList = ['Nos', 'Unit', 'Box', 'Pair', 'Set', 'Meter', 'Kg', 'Ltr', 'Pcs'];
  final List<String> _taxChargeTypes = ['On Net Total', 'Actual', 'On Previous Row Amount', 'On Previous Row Total', 'On Item Quantity'];
  final List<String> _taxCategoryOptions = ['Inter State', 'Outer State'];
  OverlayEntry? _overlayEntry;
  final TextEditingController _accountSearchController = TextEditingController();
  List<dynamic> _filteredAccountHeads = [];
  int? _activeTaxDropdownIndex;

  // --- START: STATE FOR ADDITIONAL DISCOUNT ---
  String _applyDiscountOn = 'Grand Total';
  final _additionalDiscountPercentageController = TextEditingController();
  final _additionalDiscountAmountController = TextEditingController();
  final _additionalDiscountPercentFocus = FocusNode();
  final _additionalDiscountAmountFocus = FocusNode();
  double _cachedAdditionalDiscount = 0.0;
  // --- END: STATE FOR ADDITIONAL DISCOUNT ---

  @override
  void initState() {
    super.initState();
    // --- START: ADD LISTENERS FOR DISCOUNT FIELDS ---
    _additionalDiscountPercentageController.addListener(() {
      if (_additionalDiscountPercentFocus.hasFocus) {
        _updateAdditionalDiscount(fromPercent: true);
      }
    });
    _additionalDiscountAmountController.addListener(() {
      if (_additionalDiscountAmountFocus.hasFocus) {
        _updateAdditionalDiscount(fromPercent: false);
      }
    });
    // --- END: ADD LISTENERS FOR DISCOUNT FIELDS ---

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Immediately load initial data to show the read-only view without network delay
      setState(() {
        _initialData = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;
        _isLoading = false; // Stop initial full-screen loader
      });
      // Fetch data needed for editing in the background
      _fetchEditDataInBackground();
    });
  }

  @override
  void dispose() {
    _quotationToController.dispose();
    for (var item in _selectedItems) {
      item['priceController']?.dispose();
      item['quantityController']?.dispose();
      item['discountPercentController']?.dispose();
      item['discountAmountController']?.dispose();
    }
    for (var tax in _customTaxes) {
      tax['rateController']?.dispose();
      tax['amountController']?.dispose();
      tax['descriptionController']?.dispose();
      tax['accountHeadController']?.dispose();
    }

    // --- START: DISPOSE NEW CONTROLLERS AND FOCUS NODES ---
    _additionalDiscountPercentageController.dispose();
    _additionalDiscountAmountController.dispose();
    _additionalDiscountPercentFocus.dispose();
    _additionalDiscountAmountFocus.dispose();
    // --- END: DISPOSE NEW CONTROLLERS AND FOCUS NODES ---

    _accountSearchController.dispose();
    _removeOverlay();
    super.dispose();
  }

  // --- OPTIMIZED DATA LOADING ---

  /// Fetches all data required for editing (dropdowns, item lists) in the background.
  Future<void> _fetchEditDataInBackground() async {
    // NOTE: This runs all API calls in parallel for faster loading.
    await Future.wait([
      _fetchItems(),
      _fetchCustomers(),
      _fetchSalespersons(),
      _fetchSalesTaxesTemplates(),
      _fetchAccountHeads(),
    ]);
    if (mounted) {
      setState(() {
        _isEditDataReady = true; // Enable the edit button once data is ready
      });
    }
  }

  /// Prepares the screen for editing by populating controllers and state variables.
  /// This is called only when the user clicks 'Edit' and the background data is ready.
  void _switchToEditMode() {
    _loadInitialDataForEditing();
    setState(() {
      _isEditing = true;
    });
  }

  // --- UI HELPER METHODS ---

  /// Removes the currently active overlay (for custom dropdowns).
  void _removeOverlay() {
    if (_overlayEntry != null) {
      _overlayEntry?.remove();
      _overlayEntry = null;
    }
    setState(() {
      _activeTaxDropdownIndex = null;
    });
  }

  /// Filters the list of account heads based on the search query.
  void _filterAccountHeads(String query, Function(void Function()) aSetState) {
    final filtered = query.isEmpty
        ? _accountHeads
        : _accountHeads.where((head) {
            final name = (head['account_name'] as String? ?? head['name'] as String? ?? '').toLowerCase();
            return name.contains(query.toLowerCase());
          }).toList();
    aSetState(() {
      _filteredAccountHeads = filtered;
    });
  }

  /// Provides a consistent box decoration for container-based inputs like date and selectors.
  BoxDecoration _boxDecoration() {
    return BoxDecoration(
      color: _isEditing ? Colors.white : Colors.grey.shade200,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Colors.grey.shade400),
      boxShadow: _isEditing
          ? [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 2,
                offset: const Offset(0, 1),
              )
            ]
          : [],
    );
  }

  /// Provides a consistent input decoration for TextFormFields and Dropdowns.
  InputDecoration _inputDecoration(String? labelText) {
    return InputDecoration(
      labelText: labelText,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey.shade400),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey.shade400),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Theme.of(context).primaryColor, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.red.shade400, width: 1),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      filled: true,
      fillColor: Colors.white,
      labelStyle: const TextStyle(fontSize: 14, color: Colors.black54),
      floatingLabelStyle: TextStyle(color: Theme.of(context).primaryColor),
      errorStyle: const TextStyle(fontSize: 10, height: 0.8),
      isDense: true,
    );
  }

  // --- DATA INITIALIZATION & FETCHING ---
  void _loadInitialDataForEditing() {
    if (_initialData == null) return;

    try {
      final data = _initialData!;
      _quotationToController.text = data['quotation_to']?.toString() ?? 'Customer';
      _transactionDate = DateTime.tryParse(data['transaction_date']?.toString() ?? '') ?? DateTime.now();
      _selectedTaxCategory = data['tax_category'] ?? 'Inter State';

      // --- START: LOAD ADDITIONAL DISCOUNT DATA ---
      _applyDiscountOn = data['apply_discount_on']?.toString() ?? 'Grand Total';
      final additionalDiscountPercent = (data['additional_discount_percentage'] as num?)?.toDouble() ?? 0.0;
      final additionalDiscountAmount = (data['discount_amount'] as num?)?.toDouble() ?? 0.0;
      _additionalDiscountPercentageController.text = additionalDiscountPercent.toStringAsFixed(2);
      _additionalDiscountAmountController.text = additionalDiscountAmount.toStringAsFixed(2);
      // --- END: LOAD ADDITIONAL DISCOUNT DATA ---

      final itemsFromData = (data['items'] as List<dynamic>?) ?? [];

      for (var item in itemsFromData) {
        final uom = item['uom']?.toString();
        if (uom != null && !_uomList.contains(uom)) {
          _uomList.add(uom);
        }
      }

      _selectedItems = List<Map<String, dynamic>>.from(
        itemsFromData.map((item) {
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
            'priceController': TextEditingController(
              text: ((item['price_list_rate'] ?? 0.0) as num).toDouble().toStringAsFixed(2),
            ),
            'quantityController': TextEditingController(text: (item['qty'] ?? 1).toString()),
            'discountPercentController': TextEditingController(
              text: ((item['discount_percentage'] ?? 0.0) as num).toDouble().toStringAsFixed(2),
            ),
            'discountAmountController': TextEditingController(
              text: ((item['discount_amount'] ?? 0.0) as num).toDouble().toStringAsFixed(2),
            ),
            'selectedUom': item['uom']?.toString() ?? 'Nos',
          };
        }),
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
              orElse: () => {'salesperson_name': data['sales_person']?.toString() ?? ''},
            )
          : null;

      final Map<String, List<String>> itemGeneratedTaxSources = {};
      for (final item in _selectedItems) {
        final itemCode = item['item_code'] as String;
        final fullItemData = _itemsList.firstWhere(
          (i) => i['item_code'] == itemCode,
          orElse: () => {'taxes': []},
        );
        final List<dynamic> itemTaxes = fullItemData['taxes'] ?? [];
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
        _customTaxes = List<Map<String, dynamic>>.from(
          (data['taxes'] as List<dynamic>).map((savedTax) {
            final accountHeadName = savedTax['account_head']?.toString();
            final sources = itemGeneratedTaxSources[accountHeadName] ?? [];
            final isManual = sources.isEmpty;
            final account = _accountHeads.firstWhere(
              (h) => h['name'] == accountHeadName,
              orElse: () => {'account_name': accountHeadName},
            );
            final displayName = account['account_name'] ?? accountHeadName ?? '';
            final chargeType = savedTax['charge_type']?.toString() ?? 'On Net Total';
            final rate = (savedTax['rate'] as num?)?.toDouble() ?? 0.0;
            return _createNewTaxRow(
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
    } catch (e, s) {
      debugPrint("--- ERROR LOADING QUOTATION DATA FOR EDIT ---");
      debugPrint("Error: $e");
      debugPrint("Stacktrace: $s");
      if (mounted) {
        showErrorDialog(context, 'Load Error', 'Failed to parse quotation data for editing. The data might be corrupt.');
        setState(() => _isEditing = false);
      }
    }
  }

  Map<String, String> _getHeaders() => {
        'Cookie': 'sid=${widget.sid}',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  Future<dynamic> _fetchData(String endpoint, {bool isCustomMethod = true}) async {
    final url = isCustomMethod ? "${widget.serverUrl}/api/method/$endpoint" : "${widget.serverUrl}/api/resource/$endpoint";
    try {
      final response = await retry(
        () => http.get(Uri.parse(url), headers: _getHeaders()).timeout(const Duration(seconds: 10)),
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
        _salespersonsList =
            (data['message'] as List<dynamic>).map((item) => {'salesperson_name': item['sales_person_name']?.toString() ?? ''}).toList();
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

  // --- SAVE LOGIC ---
  Future<void> _saveQuotation() async {
    _removeOverlay();
    if (!mounted) return;
    if (!_formKey.currentState!.validate()) return;
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
      if (tax['account_head'] == null || tax['account_head'].isEmpty) {
        showErrorDialog(context, 'Validation Error', 'Please select an account head for all tax rows.');
        return;
      }
    }
    setState(() => _isLoading = true);
    final itemsToSave = _selectedItems
        .map((item) => {
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
            })
        .toList();

    final taxesToSave = _calculatedTaxes.map((tax) {
      if (tax['charge_type'] == 'Actual') {
        return {
          'account_head': tax['account_head'],
          'charge_type': tax['charge_type'],
          'description': tax['description'],
          'tax_amount': tax['tax_amount'],
          'rate': 0,
        };
      } else {
        return {
          'account_head': tax['account_head'],
          'charge_type': tax['charge_type'],
          'description': tax['description'],
          'rate': tax['rate'],
        };
      }
    }).toList();

    final Map<String, dynamic> quotationData = {
      'quotation_to': _quotationToController.text.isEmpty ? 'Customer' : _quotationToController.text,
      'customer': _selectedCustomer['name']?.toString() ?? '',
      'party_name': _selectedCustomer['customer_name']?.toString() ?? '',
      'sales_person': _selectedSalesperson['salesperson_name']?.toString() ?? '',
      'transaction_date': DateFormat('yyyy-MM-dd').format(_transactionDate),
      'status': _initialData?['status']?.toString() ?? 'Draft',
      'items': itemsToSave,
      'taxes': taxesToSave,
      'tax_category': _selectedTaxCategory,
      'cost_center': 'Main - NG',
      'naming_series': _namingSeries,
      'selling_price_list': _sellingPriceList,
      'currency': _currency,
      if (_initialData != null && _initialData!['name'] != null) 'name': _initialData!['name'],
      // --- START: ADD NEW DISCOUNT FIELDS TO PAYLOAD ---
      'apply_discount_on': _applyDiscountOn,
      'additional_discount_percentage': double.tryParse(_additionalDiscountPercentageController.text) ?? 0.0,
      'discount_amount': _cachedAdditionalDiscount,
      // --- END: ADD NEW DISCOUNT FIELDS TO PAYLOAD ---
    };
    try {
      final http.Response response;
      if (_initialData == null || _initialData!['name'] == null) {
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
            Uri.parse("${widget.serverUrl}/api/resource/Quotation/${_initialData!['name']}"),
            headers: _getHeaders(),
            body: json.encode({"data": quotationData}),
          ),
        );
      }
      if (!mounted) return;
      if (response.statusCode == 200 || response.statusCode == 201) {
        final newQuotationData = json.decode(response.body)['data'];

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Quotation updated successfully!'),
            backgroundColor: Colors.green,
          ),
        );

        setState(() {
          _isEditing = false;
          _initialData = newQuotationData;
        });
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

  // --- CALCULATION & HELPER LOGIC ---

  Map<String, dynamic> _createNewTaxRow({
    required String chargeType,
    required String? accountHead,
    required String description,
    required double rate,
    List<String>? sourceItemCodes,
    required bool isManual,
  }) {
    return {
      'charge_type': chargeType,
      'account_head': accountHead,
      'description': description,
      'rate': rate,
      'source_item_codes': sourceItemCodes ?? [],
      'is_manual': isManual,
      'rateController': TextEditingController(text: rate.toStringAsFixed(2)),
      'amountController': TextEditingController(text: '0.00'),
      'descriptionController': TextEditingController(text: description),
      'accountHeadController': TextEditingController(text: description), // Display name in the text field
      'targetKey': GlobalKey(),
      'layerLink': LayerLink(),
    };
  }

  void _updateAdditionalDiscount({required bool fromPercent}) {
    // This logic depends on _performCalculations which updates _cachedTotalAmount and _calculatedTaxes
    double subtotal = _cachedTotalAmount;
    double taxTotal = _calculatedTaxes.fold(0.0, (sum, tax) => sum + (tax['tax_amount'] as double));
    double baseForDiscount = _applyDiscountOn == 'Net Total' ? subtotal : subtotal + taxTotal;

    if (fromPercent) {
      final percent = double.tryParse(_additionalDiscountPercentageController.text) ?? 0.0;
      final newAmount = (baseForDiscount * percent / 100);
      final newText = newAmount.toStringAsFixed(2);
      _additionalDiscountAmountController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: newText.length),
      );
    } else {
      final amount = double.tryParse(_additionalDiscountAmountController.text) ?? 0.0;
      final newPercent = baseForDiscount > 0 ? (amount / baseForDiscount * 100) : 0.0;
      final newText = newPercent.toStringAsFixed(2);
      _additionalDiscountPercentageController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: newText.length),
      );
    }

    setState(() {
      _performCalculations();
    });
  }

  double _calculateItemAmount(Map<String, dynamic> item) {
    double price = (item['price_list_rate'] as num?)?.toDouble() ?? 0.0;
    // Corrected to handle both 'quantity' (from local state) and 'qty' (from initial data)
    final qty = (item['quantity'] as num?)?.toInt() ?? (item['qty'] as num?)?.toInt() ?? 1;
    final discount = (item['discount_amount'] as num?)?.toDouble() ?? 0.0;
    return (price * qty - discount).clamp(0.0, double.infinity);
  }

  // MODIFIED: Calculation logic is updated to handle discounts correctly.
  void _performCalculations() {
    _cachedTotalQuantity = _selectedItems.fold(0, (sum, item) => sum + (item['quantity'] as int));
    // This is the pure item total, which we will now label as "Total"
    _cachedTotalAmount = _selectedItems.fold(0.0, (sum, item) => sum + (item['amount'] as double));

    final double additionalDiscountAmountInput = double.tryParse(_additionalDiscountAmountController.text) ?? 0.0;
    
    double taxBaseAmount;
    double finalDiscountAmount = additionalDiscountAmountInput;

    // Determine the base for tax calculation
    if (_applyDiscountOn == 'Net Total') {
      taxBaseAmount = _cachedTotalAmount - additionalDiscountAmountInput;
    } else { // 'Grand Total'
      taxBaseAmount = _cachedTotalAmount;
    }
    
    if (taxBaseAmount < 0) taxBaseAmount = 0;
    _cachedNetTotal = taxBaseAmount;

    List<Map<String, dynamic>> tempCalculatedTaxes = [];
    double grandTotalTax = 0.0;

    for (var tax in _customTaxes) {
      final String chargeType = tax['charge_type'] ?? 'On Net Total';
      double taxAmountForComponent = 0.0;
      double valueToSaveForBackend;
      
      // The taxable amount is now the calculated taxBaseAmount for most tax types
      double taxableAmount = taxBaseAmount; 
      
      if (chargeType == 'Actual') {
        taxAmountForComponent = double.tryParse(tax['amountController'].text) ?? 0.0;
        valueToSaveForBackend = taxAmountForComponent;
        if (tax['rateController'].text != '0.00') tax['rateController'].text = '0.00';
        tax['rate'] = 0.0;
      } else {
        double inputRate = double.tryParse(tax['rateController'].text) ?? tax['rate'] ?? 0.0;
        if (chargeType == 'On Item Quantity') {
          // This should still be based on quantity, not a monetary value
          taxAmountForComponent = inputRate * _cachedTotalQuantity;
          valueToSaveForBackend = inputRate;
        } else {
          // All other types are based on the monetary value
          taxAmountForComponent = (taxableAmount * inputRate / 100);
          valueToSaveForBackend = inputRate;
        }
        final newText = taxAmountForComponent.toStringAsFixed(2);
        if (tax['amountController'].text != newText) {
          tax['amountController'].value = TextEditingValue(
            text: newText,
            selection: TextSelection.collapsed(offset: newText.length),
          );
        }
      }

      grandTotalTax += taxAmountForComponent;

      tempCalculatedTaxes.add({
        'description': tax['description'],
        'charge_type': chargeType,
        'account_head': tax['account_head'],
        'tax_amount': taxAmountForComponent,
        'rate': valueToSaveForBackend,
      });
    }

    _calculatedTaxes = tempCalculatedTaxes;
    _cachedAdditionalDiscount = finalDiscountAmount;

    // Calculate Grand Total
    if (_applyDiscountOn == 'Net Total') {
      // Discount was already subtracted to get taxBaseAmount
      _cachedGrandTotal = taxBaseAmount + grandTotalTax;
    } else { // 'Grand Total'
      // Subtract discount now from the grand total
      _cachedGrandTotal = _cachedTotalAmount + grandTotalTax - finalDiscountAmount;
    }

    if(mounted) {
      setState(() {});
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

  void _removeItem(int index) {
    if (index < 0 || index >= _selectedItems.length) {
      return;
    }
    setState(() {
      final itemCodeToRemove = _selectedItems[index]['item_code'];
      _selectedItems[index]['priceController']?.dispose();
      _selectedItems[index]['quantityController']?.dispose();
      _selectedItems[index]['discountPercentController']?.dispose();
      _selectedItems[index]['discountAmountController']?.dispose();
      _selectedItems.removeAt(index);
      final taxesToKeep = <Map<String, dynamic>>[];
      final taxesToRemove = <Map<String, dynamic>>[];
      for (final tax in _customTaxes) {
        final bool isManual = tax['is_manual'] ?? false;
        if (isManual) {
          taxesToKeep.add(tax);
        } else {
          final sources = List<String>.from(tax['source_item_codes'] ?? []);
          sources.remove(itemCodeToRemove);
          if (sources.isNotEmpty) {
            tax['source_item_codes'] = sources;
            taxesToKeep.add(tax);
          } else {
            taxesToRemove.add(tax);
          }
        }
      }
      for (final tax in taxesToRemove) {
        try {
          tax['rateController']?.dispose();
          tax['amountController']?.dispose();
          tax['descriptionController']?.dispose();
          tax['accountHeadController']?.dispose();
        } catch (e) {
          debugPrint('Error disposing tax controllers: $e');
        }
      }
      _customTaxes = taxesToKeep;
      _performCalculations();
    });
  }

  // --- UI WIDGET BUILDERS ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE0F7FA),
      appBar: AppBar(
        title: Text(
          _isEditing ? 'Edit Quotation' : 'Quotation Details',
          style: const TextStyle(fontFamily: 'Dubai', color: Colors.white),
        ),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        actions: _isEditing ? _buildEditModeActions() : _buildViewModeActions(),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _isEditing
              ? _buildEditableBody()
              : _buildReadOnlyBody(),
    );
  }

  List<Widget> _buildViewModeActions() {
    final bool canEdit = _initialData != null && _initialData!['status'] == 'Draft';

    return [
      if (canEdit)
        IconButton(
          icon: _isEditDataReady
              ? const Icon(Icons.edit, color: Colors.white)
              : const SizedBox(
                  width: 24,
                  height: 24,
                  child: Padding(
                    padding: EdgeInsets.all(4.0),
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  ),
                ),
          tooltip: _isEditDataReady ? 'Edit Quotation' : 'Loading data...',
          onPressed: _isEditDataReady ? _switchToEditMode : null,
        ),
      IconButton(
        icon: const Icon(Icons.print, color: Colors.white),
        tooltip: 'Print Preview',
        onPressed: (_isLoading || _initialData == null) ? null : () => _showPrintPreview(context, _initialData!),
      ),
    ];
  }

  List<Widget> _buildEditModeActions() {
    return [
      IconButton(
        icon: const Icon(Icons.cancel, color: Colors.white),
        tooltip: 'Cancel Edit',
        onPressed: () {
          setState(() {
            _isEditing = false;
          });
        },
      ),
      TextButton(
        onPressed: _isLoading ? null : _saveQuotation,
        child: _isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
              )
            : const Text('SAVE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    ];
  }

  Widget _buildReadOnlyBody() {
    final quotation = _initialData ?? {};
    final items = (quotation['items'] as List<dynamic>?) ?? [];
    final taxes = (quotation['taxes'] as List<dynamic>? ?? []);
    final totalTaxesAndCharges = (quotation['total_taxes_and_charges'] as num?)?.toDouble() ?? 0.0;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Container(
              padding: const EdgeInsets.all(16),
              color: Colors.white,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Quotation Details', style: Theme.of(context).textTheme.titleLarge),
                  const Divider(),
                  _buildReadOnlyDetailRow('Name', quotation['name'] ?? 'N/A'),
                  _buildReadOnlyDetailRow('Customer Name', quotation['customer_name'] ?? 'N/A'),
                  _buildReadOnlyDetailRow('Contact Mobile', quotation['contact_mobile'] ?? 'N/A'),
                  _buildReadOnlyDetailRow('Quotation To', quotation['quotation_to'] ?? 'N/A'),
                  _buildReadOnlyDetailRow('Transaction Date', quotation['transaction_date'] ?? 'N/A'),
                  _buildReadOnlyDetailRow('Valid Till', quotation['valid_till'] ?? 'N/A'),
                  _buildReadOnlyDetailRow('Status', quotation['status'] ?? 'N/A'),
                  _buildReadOnlyDetailRow('Order Type', quotation['order_type'] ?? 'N/A'),
                  _buildReadOnlyDetailRow('Sales Person', quotation['sales_person'] ?? 'N/A'),
                  _buildReadOnlyDetailRow('Currency', quotation['currency'] ?? 'N/A'),
                  _buildReadOnlyDetailRow('Company', quotation['company'] ?? 'N/A'),
                  _buildReadOnlyDetailRow('GST Category', quotation['gst_category']?.toString() ?? 'N/A'),
                  // --- START: MODIFICATION TO SHOW DISCOUNT METHOD ---
                  if (quotation['discount_amount'] != null && (quotation['discount_amount'] as num? ?? 0) > 0)
                    _buildReadOnlyDetailRow('Discount On', quotation['apply_discount_on'] ?? 'N/A'),
                  // --- END: MODIFICATION TO SHOW DISCOUNT METHOD ---
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Container(
              padding: const EdgeInsets.all(16),
              color: Colors.white,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Items', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF003366))),
                  const SizedBox(height: 10),
                  if (items.isNotEmpty)
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return Card(
                          elevation: 1,
                          color: Colors.white,
                          margin: const EdgeInsets.only(bottom: 8),
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (item['image'] != null && item['image'].toString().isNotEmpty)
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8.0),
                                    child: CachedNetworkImage(
                                      imageUrl: item['image'].toString().startsWith('http')
                                          ? item['image']
                                          : '${widget.serverUrl}${item['image']}',
                                      width: 60,
                                      height: 60,
                                      fit: BoxFit.cover,
                                      placeholder: (context, url) => Container(
                                        width: 60,
                                        height: 60,
                                        color: Colors.grey[200],
                                        child: const Icon(Icons.image, color: Colors.grey),
                                      ),
                                      errorWidget: (context, url, error) => Container(
                                        width: 60,
                                        height: 60,
                                        color: Colors.grey[200],
                                        child: const Icon(Icons.broken_image, color: Colors.grey),
                                      ),
                                    ),
                                  )
                                else
                                  Container(
                                    width: 60,
                                    height: 60,
                                    decoration: BoxDecoration(
                                      color: Colors.grey[200],
                                      borderRadius: BorderRadius.circular(8.0),
                                    ),
                                    child: const Icon(Icons.image_not_supported, color: Colors.grey),
                                  ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(item['item_name'] ?? 'Unnamed Item',
                                          style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF003366))),
                                      const SizedBox(height: 4),
                                      _buildReadOnlyItemDetailRow('Quantity', '${item['qty'] ?? 'N/A'} ${item['uom'] ?? ''}'),
                                      _buildReadOnlyItemDetailRow(
                                          'Rate', (item['price_list_rate'] as num?)?.toStringAsFixed(2) ?? 'N/A'),
                                      _buildReadOnlyItemDetailRow(
                                          'Amount', (item['amount'] as num?)?.toStringAsFixed(2) ?? 'N/A'),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    )
                  else
                    const Text('No items available', style: TextStyle(color: Color(0xFF003366))),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          if (taxes.isNotEmpty || totalTaxesAndCharges > 0)
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Container(
                padding: const EdgeInsets.all(16),
                color: Colors.white,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Taxes and Charges',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF003366))),
                    const SizedBox(height: 10),
                    if (taxes.isNotEmpty)
                      ...taxes
                          .map((tax) => _buildReadOnlyItemDetailRow(
                              tax['description'] ?? 'Tax', (tax['tax_amount'] as num?)?.toStringAsFixed(2) ?? '0.00'))
                          .toList()
                    else
                      const Text('No specific tax breakdown available.', style: TextStyle(color: Color(0xFF003366))),
                    const Divider(),
                    _buildReadOnlyDetailRow('Total Taxes & Charges', totalTaxesAndCharges.toStringAsFixed(2)),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 20),
          _buildTotalsCard(),
        ],
      ),
    );
  }

  Widget _buildReadOnlyDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF003366))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 16, color: Colors.black87))),
        ],
      ),
    );
  }

  Widget _buildReadOnlyItemDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14, color: Color(0xFF424242))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 14, color: Colors.black54))),
        ],
      ),
    );
  }

  Widget _buildEditableBody() {
    return Form(
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
          _buildAdditionalDiscountSection(),
          const SizedBox(height: 8),
          _buildTotalsCard(),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildAdditionalDiscountSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(context, 'Additional Discount'),
        DropdownButtonFormField<String>(
          value: _applyDiscountOn,
          decoration: _inputDecoration('Apply Additional Discount On'),
          items: ['Grand Total', 'Net Total'].map((String value) {
            return DropdownMenuItem<String>(value: value, child: Text(value));
          }).toList(),
          onChanged: (newValue) {
            if (newValue != null) {
              setState(() {
                _applyDiscountOn = newValue;
                _performCalculations();
              });
            }
          },
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _additionalDiscountPercentageController,
                focusNode: _additionalDiscountPercentFocus,
                decoration: _inputDecoration('Discount Percentage'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                controller: _additionalDiscountAmountController,
                focusNode: _additionalDiscountAmountFocus,
                decoration: _inputDecoration('Discount Amount (INR)'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
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
      onTap: _isEditing ? () => _selectDate(context) : null,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: _boxDecoration(),
        child: Row(
          children: [
            const Icon(Icons.calendar_today, color: Color(0xFF005BAC)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                DateFormat('yyyy-MM-dd').format(_transactionDate),
                style: TextStyle(
                  color: _isEditing ? Colors.black : Colors.grey.shade600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
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

  Widget _buildCustomerSelector() {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: _isEditing
                ? () async {
                    _removeOverlay();
                    final selected = await showSearch(
                      context: context,
                      delegate: CustomerSearchDelegate(_customersList),
                    );
                    if (!mounted) return;
                    if (selected != null) {
                      setState(() {
                        _selectedCustomer = selected;
                        _selectedTaxCategory = selected['tax_category'] ?? 'Inter State';
                        _performCalculations();
                      });
                    }
                  }
                : null,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: _boxDecoration(),
              child: Row(
                children: [
                  const Icon(Icons.person, color: Color(0xFF005BAC)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _selectedCustomer?['customer_name'] ?? 'Select Customer',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _isEditing ? Colors.black : Colors.grey.shade600,
                      ),
                    ),
                  ),
                  if (_isEditing) const Icon(Icons.arrow_drop_down, color: Colors.grey),
                ],
              ),
            ),
          ),
        ),
        if (_isEditing)
          IconButton(
            icon: const Icon(Icons.add_circle_outline, color: Color(0xFF005BAC), size: 25),
            onPressed: () async {
              _removeOverlay();
              final newCustomer = await showDialog<Map<String, dynamic>>(
                context: context,
                builder: (context) => CustomerCreationDialog(
                  serverUrl: widget.serverUrl,
                  sid: widget.sid,
                ),
              );
              if (!mounted) return;
              if (newCustomer != null) {
                await _fetchCustomers();
                if (!mounted) return;
                setState(() {
                  _selectedCustomer = _customersList.firstWhere(
                    (c) => c['name'] == newCustomer['name'],
                    orElse: () => newCustomer,
                  );
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
    return _isEditing
        ? DropdownButtonFormField<String>(
            value: _selectedTaxCategory,
            decoration: _inputDecoration('Tax Category'),
            items: _taxCategoryOptions.map((String category) {
              return DropdownMenuItem<String>(value: category, child: Text(category));
            }).toList(),
            onChanged: (newValue) {
              setState(() {
                _selectedTaxCategory = newValue!;
                _performCalculations();
              });
            },
            validator: (value) => value == null ? 'Tax category is required' : null,
          )
        : Container(
            padding: const EdgeInsets.all(10),
            decoration: _boxDecoration(),
            child: Row(
              children: [
                const Icon(Icons.account_balance, color: Color(0xFF005BAC)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _selectedTaxCategory,
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ),
              ],
            ),
          );
  }

  Widget _buildSalespersonSelector() {
    return GestureDetector(
      onTap: _isEditing
          ? () async {
              _removeOverlay();
              final selected = await showSearch(
                context: context,
                delegate: SalespersonSearchDelegate(_salespersonsList),
              );
              if (!mounted) return;
              if (selected != null) setState(() => _selectedSalesperson = selected);
            }
          : null,
      child: Container(
        padding: const EdgeInsets.all(10.0),
        decoration: _boxDecoration(),
        child: Row(
          children: [
            const Icon(Icons.people_alt, color: Color(0xFF005BAC)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _selectedSalesperson?['salesperson_name'] ?? 'Select Salesperson',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _isEditing ? Colors.black : Colors.grey.shade600,
                ),
              ),
            ),
            if (_isEditing) const Icon(Icons.arrow_drop_down, color: Colors.grey),
          ],
        ),
      ),
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
                delegate: ItemSearchDelegate(items: _itemsList, serverUrl: widget.serverUrl),
              );
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
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item['item_name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                          Text('Code: ${item['item_code']}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                        ],
                      ),
                    ),
                    if (_isEditing)
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _removeItem(index),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: item['priceController'],
                        decoration: _inputDecoration('Price ₹'),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        readOnly: !_isEditing,
                        onChanged: _isEditing ? (v) => _updateItem(index, price: v) : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: item['quantityController'],
                        decoration: _inputDecoration('Qty'),
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        readOnly: !_isEditing,
                        onChanged: _isEditing ? (v) => _updateItem(index, quantity: v) : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: item['discountPercentController'],
                        decoration: _inputDecoration('Discount %'),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        readOnly: !_isEditing,
                        onChanged: _isEditing ? (v) => _updateItem(index, discountPercent: v) : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: item['discountAmountController'],
                        decoration: _inputDecoration('Discount ₹'),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        readOnly: !_isEditing,
                        onChanged: _isEditing ? (v) => _updateItem(index, discountAmount: v) : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: _isEditing
                          ? DropdownButtonFormField<String>(
                              value: item['selectedUom'],
                              decoration: _inputDecoration('UOM'),
                              isExpanded: true,
                              items: _uomList
                                  .map((uom) => DropdownMenuItem(
                                        value: uom,
                                        child: Text(uom, overflow: TextOverflow.ellipsis),
                                      ))
                                  .toList(),
                              onChanged: (v) => _updateItem(index, uom: v),
                            )
                          : Container(
                              padding: const EdgeInsets.all(10),
                              decoration: _boxDecoration(),
                              child: Text(
                                item['selectedUom'],
                                style: TextStyle(color: Colors.grey.shade600),
                              ),
                            ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 3,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          'Amt: ₹${(item['amount'] as double).toStringAsFixed(2)}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
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

  Widget _buildTaxesTable() {
    if (_customTaxes.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(
          child: Text(
            'No taxes added yet',
            style: TextStyle(color: Colors.grey, fontSize: 14),
          ),
        ),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Table(
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          columnWidths: const {
            0: FixedColumnWidth(120),
            1: FixedColumnWidth(180),
            2: FixedColumnWidth(140),
            3: FixedColumnWidth(80),
            4: FixedColumnWidth(80),
            5: FixedColumnWidth(60),
          },
          children: [
            _buildTaxTableHeader(),
            ..._customTaxes.asMap().entries.map(
                  (entry) => _buildTaxTableRow(entry.key, entry.value),
                ),
          ],
        ),
      ),
    );
  }

  TableRow _buildTaxTableHeader() {
    const style = TextStyle(fontWeight: FontWeight.bold, fontSize: 12);
    return const TableRow(
      decoration: BoxDecoration(
        color: Color(0xFFB3E5FC),
        borderRadius: BorderRadius.only(topLeft: Radius.circular(8), topRight: Radius.circular(8)),
      ),
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

  TableRow _buildTaxTableRow(int index, Map<String, dynamic> tax) {
    bool isManual = tax['is_manual'] ?? (tax['source_item_codes'] as List? ?? []).isEmpty;
    final String chargeType = tax['charge_type'] ?? 'On Net Total';

    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.all(4.0),
          child: _isEditing
              ? DropdownButtonFormField<String>(
                  value: tax['charge_type'],
                  decoration: _inputDecoration(null),
                  isExpanded: true,
                  items: _taxChargeTypes
                      .map((t) => DropdownMenuItem(
                            value: t,
                            child: Text(t, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) _updateCustomTaxRow(index, type: v);
                  },
                )
              : Container(
                  padding: const EdgeInsets.all(10),
                  child: Text(
                    tax['charge_type'],
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(4.0),
          child: CompositedTransformTarget(
            key: tax['targetKey'],
            link: tax['layerLink']!,
            child: TextFormField(
              controller: tax['accountHeadController'],
              readOnly: true,
              decoration: _inputDecoration(null).copyWith(
                errorText: tax['account_head'] == null ? 'Required' : null,
                suffixIcon: _isEditing ? const Icon(Icons.arrow_drop_down, color: Colors.grey) : null,
              ),
              onTap: _isEditing ? () => _showAccountHeadOverlay(context, index) : null,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(4.0),
          child: TextFormField(
            controller: tax['descriptionController'],
            readOnly: true,
            decoration: _inputDecoration(null).copyWith(filled: true, fillColor: Colors.grey.shade100),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(4.0),
          child: TextFormField(
            controller: tax['rateController'],
            readOnly: !_isEditing || chargeType == 'Actual' || !isManual,
            decoration: _inputDecoration(null).copyWith(
              filled: !_isEditing || chargeType == 'Actual' || !isManual,
              fillColor: (!_isEditing || chargeType == 'Actual' || !isManual) ? Colors.grey.shade100 : Colors.white,
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.center,
            onChanged: (_isEditing && isManual && chargeType != 'Actual') ? (v) => _updateCustomTaxRow(index, rate: v) : null,
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(4.0),
          child: TextFormField(
            controller: tax['amountController'],
            readOnly: !_isEditing || chargeType != 'Actual',
            decoration: _inputDecoration(null).copyWith(
              filled: !_isEditing || chargeType != 'Actual',
              fillColor: (!_isEditing || chargeType != 'Actual') ? Colors.grey.shade100 : Colors.white,
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.center,
            onChanged: (_isEditing && chargeType == 'Actual') ? (v) { setState(() => _performCalculations()); } : null,
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(4.0),
          child: SizedBox(
            width: 40,
            child: _isEditing
                ? IconButton(
                    icon: Icon(Icons.delete_outline, color: Colors.red.shade600, size: 20),
                    onPressed: () {
                      if (!isManual) {
                        showDialog(
                          context: context,
                          builder: (BuildContext context) {
                            return AlertDialog(
                              title: const Text('Delete Tax'),
                              content: Text('Are you sure you want to delete "${tax['description']}"?\n\nThis tax was added automatically from an item.'),
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
                  )
                : const SizedBox(),
          ),
        ),
      ],
    );
  }

  // MODIFIED: This widget now shows the new breakdown of totals in edit mode.
  Widget _buildTotalsCard() {
    if (_isEditing) {
      bool hasDiscount = _cachedAdditionalDiscount > 0;
      bool discountOnNetTotal = _applyDiscountOn == 'Net Total';

      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            children: [
              _buildTotalRow('Total Quantity:', '$_cachedTotalQuantity'),
              _buildTotalRow('Total:', '₹${_cachedTotalAmount.toStringAsFixed(2)}'),
              
              if (hasDiscount && discountOnNetTotal) ...[
                _buildTotalRow(
                  'Additional Discount:',
                  '- ₹${_cachedAdditionalDiscount.toStringAsFixed(2)}',
                  isNegative: true,
                ),
                const Divider(),
                _buildTotalRow('Net Total:', '₹${_cachedNetTotal.toStringAsFixed(2)}', isBold: true),
              ],
              
              if (_calculatedTaxes.isNotEmpty) const Divider(),

              ..._calculatedTaxes.map(
                (tax) => _buildTotalRow(
                  '${tax['description']}:',
                  '₹${(tax['tax_amount'] as double).toStringAsFixed(2)}',
                ),
              ),
              
              if (hasDiscount && !discountOnNetTotal)
                _buildTotalRow(
                  'Additional Discount:',
                  '- ₹${_cachedAdditionalDiscount.toStringAsFixed(2)}',
                  isNegative: true,
                ),
              
              const Divider(),
              _buildTotalRow('Grand Total:', '₹${_cachedGrandTotal.toStringAsFixed(2)}', isBold: true),
            ],
          ),
        ),
      );
    }

    // Read-only view
    final quotation = _initialData ?? {};
    final items = (quotation['items'] as List<dynamic>?) ?? [];
    final taxes = (quotation['taxes'] as List<dynamic>?) ?? [];
    final totalQuantity = items.fold<int>(0, (sum, item) => sum + ((item['qty'] as num?)?.toInt() ?? 0));
    final totalAmount = items.fold<double>(0.0, (sum, item) => sum + ((item['amount'] as num?)?.toDouble() ?? 0.0));
    final totalTaxes = taxes.fold<double>(0.0, (sum, tax) => sum + ((tax['tax_amount'] as num?)?.toDouble() ?? 0.0));
    final additionalDiscount = (quotation['discount_amount'] as num?)?.toDouble() ?? 0.0;
    final grandTotalFromApi = (quotation['grand_total'] as num?)?.toDouble() ?? (totalAmount + totalTaxes - additionalDiscount);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            _buildTotalRow('Total Quantity:', '$totalQuantity'),
            _buildTotalRow('Total:', '₹${totalAmount.toStringAsFixed(2)}'),
            if (taxes.isNotEmpty) const Divider(),
            ...taxes.map(
              (tax) => _buildTotalRow(
                '${tax['description']}:',
                '₹${(tax['tax_amount'] as num?)?.toStringAsFixed(2) ?? '0.00'}',
              ),
            ),
             if (additionalDiscount > 0)
                _buildTotalRow(
                  'Additional Discount:',
                  '- ₹${additionalDiscount.toStringAsFixed(2)}',
                  isNegative: true,
                ),
            const Divider(),
            _buildTotalRow('Grand Total:', '₹${grandTotalFromApi.toStringAsFixed(2)}', isBold: true),
          ],
        ),
      ),
    );
  }


  Widget _buildTotalRow(String label, String value, {bool isBold = false, bool isNegative = false}) {
    final style = TextStyle(
      fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
      fontSize: isBold ? 16 : 14,
      color: isNegative ? Colors.red.shade700 : null,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label, style: style), Text(value, style: style)],
      ),
    );
  }

  void _addCustomTaxRow() {
    setState(() {
      final newTax = _createNewTaxRow(
        chargeType: 'Actual',
        accountHead: null,
        description: '',
        rate: 0.0,
        isManual: true,
      );
      _customTaxes.add(newTax);
    });
  }

  void _updateItem(int index, {String? quantity, String? price, String? discountPercent, String? discountAmount, String? uom}) {
    setState(() {
      final item = _selectedItems[index];

      if (quantity != null) {
        item['quantity'] = int.tryParse(quantity) ?? 1;
        if (item['quantity'] <= 0) {
          _removeItem(index);
          return;
        }
      }

      if (price != null) {
        item['price_list_rate'] = double.tryParse(price) ?? 0.0;
      }

      final currentPrice = item['price_list_rate'] as double;
      final currentQty = item['quantity'] as int;

      if (discountPercent != null) {
        final percent = double.tryParse(discountPercent) ?? 0.0;
        item['discount_percent'] = percent;
        final newDiscountAmount = (currentPrice * currentQty * percent / 100);
        item['discount_amount'] = newDiscountAmount;
        final newText = newDiscountAmount.toStringAsFixed(2);
        item['discountAmountController'].value = TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: newText.length),
        );
      } else if (discountAmount != null) {
        final amount = double.tryParse(discountAmount) ?? 0.0;
        final subtotal = currentPrice * currentQty;
        item['discount_amount'] = amount;
        final newDiscountPercent = subtotal > 0 ? (amount / subtotal * 100) : 0.0;
        item['discount_percent'] = newDiscountPercent;
        final newText = newDiscountPercent.toStringAsFixed(2);
        item['discountPercentController'].value = TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: newText.length),
        );
      } else if (price != null || quantity != null) {
        final percent = item['discount_percent'] as double;
        final newDiscountAmount = (currentPrice * currentQty * percent / 100);
        item['discount_amount'] = newDiscountAmount;
        final newText = newDiscountAmount.toStringAsFixed(2);
        item['discountAmountController'].value = TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: newText.length),
        );
      }

      if (uom != null) item['selectedUom'] = uom;

      item['amount'] = _calculateItemAmount(item);
      _performCalculations();
    });
  }

  void _updateCustomTaxRow(int index, {String? type, String? accountHead, String? rate}) {
    if (index < 0 || index >= _customTaxes.length) {
      return;
    }
    setState(() {
      final tax = _customTaxes[index];

      if (type != null) {
        tax['charge_type'] = type;
        if (type == 'Actual') {
          tax['rate'] = 0.0;
          tax['rateController'].text = '0.00';
        }
      }

      if (accountHead != null) {
        tax['account_head'] = accountHead;
        final selectedAccount = _accountHeads.firstWhere(
          (acc) => acc['name'] == accountHead,
          orElse: () => {'account_name': accountHead},
        );
        final accountName = selectedAccount['account_name'] ?? accountHead;
        tax['description'] = accountName;
        tax['descriptionController'].text = accountName;
        tax['accountHeadController'].text = accountName;
      }

      if (rate != null) {
        final rateValue = double.tryParse(rate) ?? 0.0;
        tax['rate'] = rateValue;
      }

      _performCalculations();
    });
  }

  void _removeCustomTaxRow(int index) {
    _removeOverlay();

    setState(() {
      if (index < 0 || index >= _customTaxes.length) {
        return;
      }
      final tax = _customTaxes[index];
      final bool isManual = tax['is_manual'] ?? false;
      final String? accountHead = tax['account_head'];
      if (!isManual && accountHead != null && accountHead.isNotEmpty) {
        _manuallyRemovedTaxes.add(accountHead);
      }
      try {
        tax['rateController']?.dispose();
        tax['amountController']?.dispose();
        tax['descriptionController']?.dispose();
        tax['accountHeadController']?.dispose();
      } catch (e) {
        debugPrint('Error disposing controllers: $e');
      }
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

  void _showAccountHeadOverlay(BuildContext context, int taxIndex) {
    if (_accountHeads.isEmpty) {
      if (!mounted) return;
      showErrorDialog(context, 'No Account Heads', 'No account heads available. Please check the API connection.');
      return;
    }

    _removeOverlay();
    setState(() {
      _activeTaxDropdownIndex = taxIndex;
    });
    final taxData = _customTaxes[taxIndex];
    final targetKey = taxData['targetKey'] as GlobalKey?;
    final layerLink = taxData['layerLink'] as LayerLink;
    final targetContext = targetKey?.currentContext;
    if (targetContext == null) {
      if (!mounted) return;
      showErrorDialog(context, 'Render Error', 'Cannot display dropdown due to rendering issue.');
      return;
    }
    final renderBox = targetContext.findRenderObject() as RenderBox;
    final size = renderBox.size;
    _filteredAccountHeads = _accountHeads;
    _accountSearchController.clear();

    _overlayEntry = OverlayEntry(
      builder: (context) => StatefulBuilder(builder: (context, aSetState) {
        return Stack(
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
                link: layerLink,
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
                            onChanged: (query) => _filterAccountHeads(query, aSetState),
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
                                      title: Text(
                                        accountName,
                                        style: const TextStyle(fontSize: 14),
                                        overflow: TextOverflow.ellipsis,
                                      ),
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
        );
      }),
    );

    if (mounted) {
      Overlay.of(context).insert(_overlayEntry!);
    }
  }

  Future<void> _scanBarcode() async {
    if (!_isEditing) return;
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
        'priceController': TextEditingController(text: ((item['price_list_rate'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2)),
        'quantityController': TextEditingController(text: '1'),
        'discountPercentController': TextEditingController(text: '0.00'),
        'discountAmountController': TextEditingController(text: '0.00'),
        'selectedUom': defaultUom,
      });
      // Add taxes from item if they match the selected tax category
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
    final existingTaxIndex = _customTaxes.indexWhere((t) => t['account_head'] == accountHeadName);
    if (existingTaxIndex != -1) {
      final tax = _customTaxes[existingTaxIndex];
      if (tax['source_item_codes'] is List) {
        if (!(tax['source_item_codes'] as List).contains(itemCode)) {
          (tax['source_item_codes'] as List).add(itemCode);
        }
      }
    } else {
      final account = _accountHeads.firstWhere(
        (h) => h['name'] == accountHeadName,
        orElse: () => {'account_name': accountHeadName},
      );
      final displayName = account['account_name'] ?? accountHeadName;
      final chargeType = taxComponent['charge_type'] ?? 'On Net Total';
      final rate = (taxComponent['rate'] as num?)?.toDouble() ?? 0.0;
      final newTax = _createNewTaxRow(
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

  // --- PDF GENERATION (NEW CODE) ---

  void _showPrintPreview(BuildContext context, Map<String, dynamic> quotation) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(10),
        child: SizedBox(
          width: MediaQuery.of(context).size.width * 0.9,
          height: MediaQuery.of(context).size.height * 0.8,
          child: PdfPreview(
            build: (format) => _generatePdf(quotation, widget.serverUrl), // Pass serverUrl
            canChangePageFormat: false,
            canDebug: false,
            initialPageFormat: PdfPageFormat.a4,
            allowSharing: true,
            allowPrinting: true,
          ),
        ),
      ),
    );
  }

  Future<Uint8List> _generatePdf(Map quotation, String serverUrl) async {
    final pdf = pw.Document();
    pw.Font? font;
    try {
      font = await PdfGoogleFonts.notoSansRegular();
    } catch (e) {
      debugPrint('Error loading font: $e');
      font = pw.Font.helvetica(); // Fallback to Helvetica
    }

    final Uint8List logoData = (await rootBundle.load('assets/images/logo.jpg')).buffer.asUint8List();
    final pw.MemoryImage logoImage = pw.MemoryImage(logoData);

    final List<dynamic> items = quotation['items'] ?? [];
    final List<dynamic> taxesList = quotation['taxes'] ?? [];

    double subtotal = items.fold<double>(
      0.0,
      (sum, item) => sum + ((item['amount'] ?? 0).toDouble()),
    );

    double totalTaxesAndCharges = (quotation['total_taxes_and_charges'] != null)
        ? quotation['total_taxes_and_charges'].toDouble()
        : taxesList.fold<double>(
            0.0,
            (sum, tax) => sum + ((tax['tax_amount'] ?? 0).toDouble()),
          );

    int totalQty = items.fold<int>(
      0,
      (sum, item) => sum + ((item['qty'] ?? 0) as num).toInt(),
    );
    
    final double additionalDiscount = (quotation['discount_amount'] as num?)?.toDouble() ?? 0.0;
    final grandTotalFromApi = (quotation['grand_total'] as num?)?.toDouble() ?? (subtotal + totalTaxesAndCharges - additionalDiscount);

    int roundedTotal = grandTotalFromApi.round();
    String inWords = 'INR ${_numberToWordsIndian(roundedTotal)} only';

    List<String> customerNameLines = _splitTextIntoLines(quotation['customer_name'] ?? 'N/A', 25);
    List<String> mobileNoLines = _splitTextIntoLines(quotation['contact_mobile'] ?? 'N/A', 25);
    List<String> dateLines = _splitTextIntoLines(quotation['transaction_date'] ?? DateFormat('dd-MM-yyyy').format(DateTime.now()), 25);
    List<String> validTillLines =
        _splitTextIntoLines(quotation['valid_till'] ?? DateFormat('dd-MM-yyyy').format(DateTime.now().add(const Duration(days: 30))), 25);
    List<String> userNameLines = _splitTextIntoLines(quotation['user_name'] ?? 'N/A', 25);
    List<String> salesPersonLines = _splitTextIntoLines(quotation['sales_person'] ?? 'N/A', 25);
    List<String> remarksLines = _splitTextIntoLines(quotation['remarks'] ?? 'N/A', 25);
    List<String> quoteNoLines = _splitTextIntoLines(quotation['name'] ?? 'N/A', 25);
    List<String> gstCategoryLines = _splitTextIntoLines(quotation['gst_category']?.toString() ?? 'N/A', 25);
    List<String> inWordsLines = _splitTextIntoLines(inWords, 50);

    bool showSalesPerson = quotation['sales_person'] != null && quotation['sales_person'].toString().isNotEmpty && quotation['sales_person'] != 'N/A';
    bool showRemarks = quotation['remarks'] != null && quotation['remarks'].toString().isNotEmpty && quotation['remarks'] != 'N/A';

    List<pw.MemoryImage?> itemImages = [];
    if (quotation['items'] != null && (quotation['items'] as List).isNotEmpty) {
      for (var item in quotation['items']) {
        if (item['image'] != null && item['image'].isNotEmpty) {
          try {
            String imageUrlString = item['image'].startsWith('http') ? item['image'] : '$serverUrl${item['image']}';

            final response = await http.get(
              Uri.parse(Uri.encodeFull(imageUrlString)),
            );
            if (response.statusCode == 200) {
              itemImages.add(pw.MemoryImage(response.bodyBytes));
            } else {
              itemImages.add(null);
              debugPrint('Failed to load image for PDF: ${item['item_name']} - Status: ${response.statusCode}');
            }
          } catch (e) {
            debugPrint('Error loading image for ${item['item_name']} for PDF: $e');
            itemImages.add(null);
          }
        } else {
          itemImages.add(null);
        }
      }
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(56.7), // 2cm margins
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Image(logoImage, width: 60, height: 60),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Text(
                      'QUOTATION',
                      style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, font: font),
                    ),
                    pw.Text(
                      'HOME MART',
                      style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, font: font),
                    ),
                  ],
                ),
                pw.SizedBox(width: 60),
              ],
            ),
            pw.SizedBox(height: 12),
            pw.Divider(thickness: 1, color: PdfColors.black),
          ],
        ),
        footer: (context) => pw.Container(
          alignment: pw.Alignment.center,
          margin: const pw.EdgeInsets.only(top: 10),
          child: pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: pw.TextStyle(fontSize: 10, font: font),
          ),
        ),
        build: (pw.Context context) => [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                flex: 1,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _buildPdfDetailRow('Customer Name:', customerNameLines, font),
                    pw.SizedBox(height: 8),
                    _buildPdfDetailRow('Mobile No:', mobileNoLines, font),
                    pw.SizedBox(height: 8),
                    _buildPdfDetailRow('GST Category:', gstCategoryLines, font),
                  ],
                ),
              ),
              pw.SizedBox(width: 20),
              pw.Expanded(
                flex: 1,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _buildPdfDetailRow('Quote No.:', quoteNoLines, font),
                    pw.SizedBox(height: 8),
                    _buildPdfDetailRow('Date:', dateLines, font),
                    pw.SizedBox(height: 8),
                    _buildPdfDetailRow('Valid Till:', validTillLines, font),
                    pw.SizedBox(height: 8),
                    _buildPdfDetailRow('User Name:', userNameLines, font),
                    if (showSalesPerson) ...[
                      pw.SizedBox(height: 8),
                      _buildPdfDetailRow('Sales Person:', salesPersonLines, font),
                    ],
                    if (showRemarks) ...[
                      pw.SizedBox(height: 8),
                      _buildPdfDetailRow('Remarks:', remarksLines, font),
                    ],
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 20),
          pw.Text(
            'Items',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, font: font),
          ),
          pw.SizedBox(height: 8),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.black),
            columnWidths: {
              0: const pw.FixedColumnWidth(30),
              1: const pw.FlexColumnWidth(2),
              2: const pw.FixedColumnWidth(50),
              3: const pw.FixedColumnWidth(60),
              4: const pw.FixedColumnWidth(60),
              5: const pw.FixedColumnWidth(60),
              6: const pw.FixedColumnWidth(60),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  pw.Container(
                      alignment: pw.Alignment.center,
                      padding: const pw.EdgeInsets.all(5),
                      child: pw.Text('Sr', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, font: font))),
                  pw.Container(
                      alignment: pw.Alignment.centerLeft,
                      padding: const pw.EdgeInsets.all(5),
                      child: pw.Text('Item Name', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, font: font))),
                  pw.Container(
                      alignment: pw.Alignment.center,
                      padding: const pw.EdgeInsets.all(5),
                      child: pw.Text('Image', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, font: font))),
                  pw.Container(
                      alignment: pw.Alignment.center,
                      padding: const pw.EdgeInsets.all(5),
                      child: pw.Text('Qty/UOM', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, font: font))),
                  pw.Container(
                      alignment: pw.Alignment.center,
                      padding: const pw.EdgeInsets.all(5),
                      child: pw.Text('List Rate', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, font: font))),
                  pw.Container(
                      alignment: pw.Alignment.center,
                      padding: const pw.EdgeInsets.all(5),
                      child: pw.Text('After Disc', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, font: font))),
                  pw.Container(
                      alignment: pw.Alignment.center,
                      padding: const pw.EdgeInsets.all(5),
                      child: pw.Text('Amount', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, font: font))),
                ],
              ),
              if (items.isNotEmpty)
                ...List.generate(items.length, (index) {
                  final item = items[index];
                  final mrp = item['price_list_rate']?.toDouble() ?? 0.0;
                  final afterDisc = item['rate']?.toDouble() ?? 0.0;
                  final amount = item['amount']?.toDouble() ?? 0.0;
                  final qtyUom = '${item['qty']?.toString() ?? 'N/A'}/${item['uom'] ?? 'N/A'}';
                  return pw.TableRow(
                    children: [
                      pw.Container(
                          alignment: pw.Alignment.center,
                          padding: const pw.EdgeInsets.all(5),
                          child: pw.Text('${index + 1}', style: pw.TextStyle(fontSize: 10, font: font))),
                      pw.Container(
                          alignment: pw.Alignment.centerLeft,
                          padding: const pw.EdgeInsets.all(5),
                          child: pw.Text(item['item_name'] ?? 'N/A', style: pw.TextStyle(fontSize: 10, font: font))),
                      pw.Container(
                        alignment: pw.Alignment.center,
                        padding: const pw.EdgeInsets.all(5),
                        child: itemImages[index] != null
                            ? pw.Image(itemImages[index]!, width: 30, height: 30, fit: pw.BoxFit.cover)
                            : pw.SizedBox(width: 30, height: 30),
                      ),
                      pw.Container(
                          alignment: pw.Alignment.center,
                          padding: const pw.EdgeInsets.all(5),
                          child: pw.Text(qtyUom, style: pw.TextStyle(fontSize: 10, font: font))),
                      pw.Container(
                          alignment: pw.Alignment.centerRight,
                          padding: const pw.EdgeInsets.all(5),
                          child: pw.Text(mrp.toStringAsFixed(2), style: pw.TextStyle(fontSize: 10, font: font))),
                      pw.Container(
                          alignment: pw.Alignment.centerRight,
                          padding: const pw.EdgeInsets.all(5),
                          child: pw.Text(afterDisc.toStringAsFixed(2), style: pw.TextStyle(fontSize: 10, font: font))),
                      pw.Container(
                          alignment: pw.Alignment.centerRight,
                          padding: const pw.EdgeInsets.all(5),
                          child: pw.Text(amount.toStringAsFixed(2), style: pw.TextStyle(fontSize: 10, font: font))),
                    ],
                  );
                })
              else
                pw.TableRow(
                  children: [
                    pw.Container(),
                    pw.Container(
                        alignment: pw.Alignment.center,
                        padding: const pw.EdgeInsets.all(5),
                        child: pw.Text('No items available', style: pw.TextStyle(fontSize: 10, font: font))),
                    pw.Container(),
                    pw.Container(),
                    pw.Container(),
                    pw.Container(),
                    pw.Container(),
                  ],
                ),
            ],
          ),
          pw.SizedBox(height: 20),
          if (taxesList.isNotEmpty || totalTaxesAndCharges > 0) ...[
            pw.Text(
              'Taxes and Charges',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, font: font),
            ),
            pw.SizedBox(height: 8),
            if (taxesList.isNotEmpty)
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.black),
                columnWidths: {
                  0: const pw.FlexColumnWidth(2),
                  1: const pw.FixedColumnWidth(80),
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                    children: [
                      pw.Container(
                          alignment: pw.Alignment.centerLeft,
                          padding: const pw.EdgeInsets.all(5),
                          child: pw.Text('Description', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, font: font))),
                      pw.Container(
                          alignment: pw.Alignment.centerRight,
                          padding: const pw.EdgeInsets.all(5),
                          child: pw.Text('Tax Amount', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, font: font))),
                    ],
                  ),
                  ...taxesList.map((tax) {
                    return pw.TableRow(
                      children: [
                        pw.Container(
                            alignment: pw.Alignment.centerLeft,
                            padding: const pw.EdgeInsets.all(5),
                            child: pw.Text(tax['description'] ?? 'N/A', style: pw.TextStyle(fontSize: 10, font: font))),
                        pw.Container(
                            alignment: pw.Alignment.centerRight,
                            padding: const pw.EdgeInsets.all(5),
                            child: pw.Text((tax['tax_amount']?.toDouble() ?? 0.0).toStringAsFixed(2),
                                style: pw.TextStyle(fontSize: 10, font: font))),
                      ],
                    );
                  }).toList(),
                ],
              )
            else
              pw.Text(
                'No specific tax breakdown available.',
                style: pw.TextStyle(fontSize: 10, font: font),
              ),
            pw.SizedBox(height: 8),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(
                'Total Taxes and Charges: ₹${totalTaxesAndCharges.toStringAsFixed(2)}',
                style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, font: font),
              ),
            ),
            pw.SizedBox(height: 20),
          ],
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                flex: 1,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Total Quantity: $totalQty',
                      style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, font: font),
                    ),
                  ],
                ),
              ),
              // --- START: REFACTORED PDF TOTALS TO MATCH UI ---
              pw.Expanded(
                flex: 1,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Subtotal (Items):', style: pw.TextStyle(fontSize: 12, font: font)),
                        pw.Text('₹${subtotal.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 12, font: font)),
                      ],
                    ),
                    if (additionalDiscount > 0) ...[
                      pw.SizedBox(height: 8),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('Additional Discount:', style: pw.TextStyle(fontSize: 12, font: font, color: PdfColors.red)),
                          pw.Text('- ₹${additionalDiscount.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 12, font: font, color: PdfColors.red)),
                        ],
                      ),
                    ],
                    pw.SizedBox(height: 8),
                    pw.Divider(thickness: 0.5),
                    pw.SizedBox(height: 4),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Grand Total:', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, font: font)),
                        pw.Text('₹${grandTotalFromApi.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, font: font)),
                      ],
                    ),
                    pw.SizedBox(height: 8),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Rounded Total:', style: pw.TextStyle(fontSize: 12, font: font)),
                        pw.Text('₹${roundedTotal.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 12, font: font)),
                      ],
                    ),
                  ],
                ),
              ),
              // --- END: REFACTORED PDF TOTALS TO MATCH UI ---
            ],
          ),
          pw.SizedBox(height: 16),
          pw.Text(
            'Amount in Words:',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, font: font),
          ),
          ...inWordsLines.map((line) => pw.Text(line, style: pw.TextStyle(fontSize: 12, font: font))),
          pw.SizedBox(height: 40),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Container(width: 150, child: pw.Divider(thickness: 1, color: PdfColors.black)),
                  pw.Text(
                    'Customer\'s Signature',
                    style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, font: font),
                  ),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Container(width: 150, child: pw.Divider(thickness: 1, color: PdfColors.black)),
                  pw.Text(
                    'Authorized Signature',
                    style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, font: font),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );

    return await pdf.save();
  }

  pw.Widget _buildPdfDetailRow(String label, List<String> lines, pw.Font? font) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.start,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, font: font),
        ),
        pw.SizedBox(width: 5),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: lines.map((line) => pw.Text(line, style: pw.TextStyle(fontSize: 12, font: font))).toList(),
          ),
        ),
      ],
    );
  }

  String _numberToWordsIndian(int number) {
    if (number == 0) return 'Zero';
    const List units = [
      '', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine', 'Ten',
      'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen', 'Seventeen', 'Eighteen', 'Nineteen',
    ];
    const List tens = ['', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety'];
    List parts = [];
    int crore = number ~/ 10000000;
    number %= 10000000;
    int lakh = number ~/ 100000;
    number %= 100000;
    int thousand = number ~/ 1000;
    number %= 1000;
    int hundred = number ~/ 100;
    number %= 100;
    int remaining = number;
    if (crore > 0) parts.add('${_convertLessThanThousand(crore)} Crore');
    if (lakh > 0) parts.add('${_convertLessThanThousand(lakh)} Lakh');
    if (thousand > 0) parts.add('${_convertLessThanThousand(thousand)} Thousand');
    if (hundred > 0) parts.add('${units[hundred]} Hundred');
    if (remaining > 0) parts.add(_convertLessThanThousand(remaining));
    return parts.join(' ').trim();
  }

  String _convertLessThanThousand(int number) {
    const List units = [
      '', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine', 'Ten',
      'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen', 'Seventeen', 'Eighteen', 'Nineteen',
    ];
    const List tens = ['', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety'];
    if (number == 0) return '';
    if (number < 20) return units[number];
    int ten = number ~/ 10;
    int unit = number % 10;
    return '${tens[ten]}${unit > 0 ? ' ${units[unit]}' : ''}'.trim();
  }

  List<String> _splitTextIntoLines(String text, int maxLineLength) {
    List<String> lines = [];
    List<String> words = text.split(' ');
    String currentLine = '';
    for (String word in words) {
      if (currentLine.isEmpty) {
        currentLine = word;
      } else if ((currentLine.length + word.length + 1) <= maxLineLength) {
        currentLine += ' $word';
      } else {
        lines.add(currentLine);
        currentLine = word;
      }
    }
    if (currentLine.isNotEmpty) {
      lines.add(currentLine);
    }
    return lines;
  }
}

// --- Helper classes (CustomerCreationDialog, SearchDelegates) ---

class CustomerCreationDialog extends StatefulWidget {
  final String serverUrl;
  final String sid;
  const CustomerCreationDialog({super.key, required this.serverUrl, required this.sid});
  @override
  _CustomerCreationDialogState createState() => _CustomerCreationDialogState();
}

class _CustomerCreationDialogState extends State<CustomerCreationDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _mobileController = TextEditingController();
  bool _isLoading = false;

  Future<void> _createCustomer() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    final data = {
      "customer_name": _nameController.text,
      "mobile_no": _mobileController.text,
      "customer_type": "Individual", // default value
    };
    try {
      final response = await http.post(
        Uri.parse("${widget.serverUrl}/api/resource/Customer"),
        headers: {'Cookie': 'sid=${widget.sid}', 'Content-Type': 'application/json'},
        body: json.encode({"data": data}),
      );
      if (!mounted) return;
      if (response.statusCode == 200) {
        final newCustomer = json.decode(response.body)['data'];
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Customer created successfully'), backgroundColor: Colors.green));
        Navigator.pop(context, newCustomer);
      } else {
        showApiErrorDialog(context, statusCode: response.statusCode, message: response.body);
      }
    } catch (e) {
      if (!mounted) return;
      showErrorDialog(context, "Error", "Failed to create customer: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create New Customer'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Customer Name'),
              validator: (value) => value!.isEmpty ? 'Please enter a name' : null,
            ),
            TextFormField(
              controller: _mobileController,
              decoration: const InputDecoration(labelText: 'Mobile Number'),
              keyboardType: TextInputType.phone,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _isLoading ? null : _createCustomer,
          child: _isLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save'),
        ),
      ],
    );
  }
}

class CustomerSearchDelegate extends SearchDelegate<dynamic> {
  final List<dynamic> customers;
  CustomerSearchDelegate(this.customers);

  @override
  List<Widget>? buildActions(BuildContext context) => [IconButton(icon: const Icon(Icons.clear), onPressed: () => query = '')];
  @override
  Widget? buildLeading(BuildContext context) => IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => close(context, null));

  @override
  Widget buildResults(BuildContext context) => _buildSuggestionsList();
  @override
  Widget buildSuggestions(BuildContext context) => _buildSuggestionsList();

  Widget _buildSuggestionsList() {
    final suggestions = query.isEmpty
        ? customers
        : customers.where((c) {
            final name = c['customer_name']?.toString().toLowerCase() ?? '';
            return name.contains(query.toLowerCase());
          }).toList();
    return ListView.builder(
      itemCount: suggestions.length,
      itemBuilder: (context, index) {
        final customer = suggestions[index];
        return ListTile(
          title: Text(customer['customer_name'] ?? 'N/A'),
          subtitle: Text('ID: ${customer['name'] ?? 'N/A'}'),
          onTap: () => close(context, customer),
        );
      },
    );
  }
}

class SalespersonSearchDelegate extends SearchDelegate<dynamic> {
  final List<dynamic> salespersons;
  SalespersonSearchDelegate(this.salespersons);

  @override
  List<Widget>? buildActions(BuildContext context) => [IconButton(icon: const Icon(Icons.clear), onPressed: () => query = '')];
  @override
  Widget? buildLeading(BuildContext context) => IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => close(context, null));

  @override
  Widget buildResults(BuildContext context) => _buildSuggestionsList();
  @override
  Widget buildSuggestions(BuildContext context) => _buildSuggestionsList();

  Widget _buildSuggestionsList() {
    final suggestions = query.isEmpty
        ? salespersons
        : salespersons.where((sp) {
            final name = sp['salesperson_name']?.toString().toLowerCase() ?? '';
            return name.contains(query.toLowerCase());
          }).toList();
    return ListView.builder(
      itemCount: suggestions.length,
      itemBuilder: (context, index) {
        final salesperson = suggestions[index];
        return ListTile(
          title: Text(salesperson['salesperson_name'] ?? 'N/A'),
          onTap: () => close(context, salesperson),
        );
      },
    );
  }
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
  Widget buildResults(BuildContext context) => _buildSuggestionsList();
  @override
  Widget buildSuggestions(BuildContext context) => _buildSuggestionsList();

  Widget _buildSuggestionsList() {
    final suggestions = query.isEmpty
        ? items
        : items.where((i) {
            final name = i['item_name']?.toString().toLowerCase() ?? '';
            final code = i['item_code']?.toString().toLowerCase() ?? '';
            final q = query.toLowerCase();
            return name.contains(q) || code.contains(q);
          }).toList();
    return ListView.builder(
      itemCount: suggestions.length,
      itemBuilder: (context, index) {
        final item = suggestions[index];
        final imageUrl = item['image'];
        return ListTile(
          leading: (imageUrl != null && imageUrl.isNotEmpty)
              ? CachedNetworkImage(
                  imageUrl: imageUrl.startsWith('http') ? imageUrl : '$serverUrl$imageUrl',
                  width: 50,
                  height: 50,
                  fit: BoxFit.cover,
                  errorWidget: (c, u, e) => const Icon(Icons.broken_image),
                )
              : const Icon(Icons.image_not_supported, size: 50),
          title: Text(item['item_name'] ?? 'N/A'),
          subtitle: Text('Code: ${item['item_code'] ?? 'N/A'}'),
          onTap: () => close(context, item),
        );
      },
    );
  }
}
