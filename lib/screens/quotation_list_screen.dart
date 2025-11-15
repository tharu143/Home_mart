import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
// import 'package:home_mart/error_handler.dart'; // Import error handler - Assuming you have this file

// Mock Error Handler since the original was not provided
void showApiErrorDialog(BuildContext context, {required int statusCode, required String message}) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('API Error: $statusCode'),
      content: SingleChildScrollView(child: Text(message)),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
    ),
  );
}

void showErrorDialog(BuildContext context, String title, String message) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
    ),
  );
}
// End Mock Error Handler

class QuotationListScreen extends StatefulWidget {
  final String serverUrl;
  final String sid;

  const QuotationListScreen({
    super.key,
    required this.serverUrl,
    required this.sid,
  });

  @override
  State<QuotationListScreen> createState() => _QuotationListScreenState();
}

class _QuotationListScreenState extends State<QuotationListScreen>
    with SingleTickerProviderStateMixin {
  List<dynamic> _quotations = [];
  List<dynamic> _filteredQuotations = [];
  bool _isLoading = false;
  bool _hasMore = true;
  int _page = 1;
  final int _pageSize = 10; // Load 10 items per page
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  Map<String, dynamic>? _cachedData; // Simple in-memory cache
  final ScrollController _scrollController = ScrollController();
  late AnimationController _listAnimationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    // Validate SID before proceeding
    if (widget.sid.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.pushReplacementNamed(context, '/');
      });
    } else {
      _loadQuotations();
      _searchController.addListener(_onSearchChanged);
      _scrollController.addListener(_onScroll);
      // Initialize animation controller for list items
      _listAnimationController = AnimationController(
        duration: const Duration(milliseconds: 500),
        vsync: this,
      );
      _fadeAnimation = CurvedAnimation(
        parent: _listAnimationController,
        curve: Curves.easeInOut,
      );
      _listAnimationController.forward();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    _debounce?.cancel();
    _listAnimationController.dispose();
    super.dispose();
  }

  Map<String, String> _getHeaders() => {
        'Cookie': 'sid=${widget.sid}',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  Future<void> _loadQuotations({bool isRefresh = false}) async {
    if (_isLoading || (!_hasMore && !isRefresh)) return;
    setState(() => _isLoading = true);
    if (isRefresh) {
      _page = 1;
      _quotations.clear();
      _filteredQuotations.clear();
      _hasMore = true;
    }
    try {
      final response = await http.get(
        Uri.parse(
          '${widget.serverUrl}/api/method/custom_scripts.API.qtn.get_quotation_details1?page=$_page&limit=$_pageSize',
        ),
        headers: _getHeaders(),
      );
      debugPrint('Response Status: ${response.statusCode}');
      debugPrint('Response Body: ${response.body}');
      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        // Handle both 'data' and 'message' keys for robustness
        final List<dynamic> data =
            jsonResponse['data'] ?? jsonResponse['message'] ?? [];
        // Validate data structure
        if (data.isNotEmpty &&
            !data.every((item) => item is Map<String, dynamic>)) {
          throw const FormatException('Invalid quotation data format');
        }
        setState(() {
          if (isRefresh) {
            _quotations = data;
          } else {
            _quotations.addAll(data);
          }
          _filterQuotations();
          _page++;
          _hasMore = data.length == _pageSize;
          _isLoading = false;
        });
        // Cache the response
        _cachedData = {'data': _quotations, 'timestamp': DateTime.now()};
      } else {
        if (!mounted) return;
        showApiErrorDialog(
          context,
          statusCode: response.statusCode,
          message: response.body,
        );
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (!mounted) return;
      showErrorDialog(context, 'Network Error', 'Error loading quotations: $e');
      setState(() => _isLoading = false);
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels ==
            _scrollController.position.maxScrollExtent &&
        !_isLoading) {
      _loadQuotations();
    }
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _filterQuotations();
    });
  }

  void _filterQuotations() {
    String query = _searchController.text.toLowerCase();
    setState(() {
      _filteredQuotations = _quotations.where((quote) {
        return (quote['name']?.toLowerCase().contains(query) ?? false) ||
            (quote['quotation_to']?.toLowerCase().contains(query) ?? false) ||
            (quote['transaction_date']?.toLowerCase().contains(query) ??
                false) ||
            (quote['customer_name']?.toLowerCase().contains(query) ?? false);
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 400;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quotations'),
        backgroundColor: Theme.of(context).primaryColor,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).scaffoldBackgroundColor,
              Theme.of(context).colorScheme.surface,
            ],
          ),
        ),
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.all(isSmallScreen ? 12.0 : 16.0),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search by name, date, customer',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  prefixIcon: Icon(
                    Icons.search,
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                ),
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => _loadQuotations(isRefresh: true),
                child: _filteredQuotations.isEmpty && !_isLoading
                    ? const Center(
                        child: Text(
                          'No quotations found',
                          style: TextStyle(color: Color(0xFF003366)),
                        ),
                      )
                    : ListView.separated(
                        controller: _scrollController,
                        padding: EdgeInsets.all(isSmallScreen ? 12.0 : 16.0),
                        itemCount:
                            _filteredQuotations.length + (_hasMore ? 1 : 0),
                        separatorBuilder: (_, __) => SizedBox(
                          height: isSmallScreen ? 6 : 8,
                        ),
                        itemBuilder: (context, index) {
                          if (index == _filteredQuotations.length && _hasMore) {
                            return const Center(
                              child: Padding(
                                padding: EdgeInsets.all(8.0),
                                child: CircularProgressIndicator(
                                  color: Color(0xFF00B4D8),
                                ),
                              ),
                            );
                          }
                          final quote = _filteredQuotations[index];
                          return _buildAnimatedQuotationCard(quote, index);
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: ScaleTransition(
        scale: _fadeAnimation,
        child: FloatingActionButton(
          onPressed: () async {
            if (widget.sid.isEmpty) {
              showErrorDialog(context, 'Session Error',
                  'Invalid session. Please log in again.');
              Navigator.pushNamedAndRemoveUntil(
                  context, '/', (route) => false);
              return;
            }
            await Navigator.pushNamed(
              context,
              '/quotation',
              arguments: {'sid': widget.sid, 'serverUrl': widget.serverUrl},
            );
            _loadQuotations(isRefresh: true);
          },
          backgroundColor: Theme.of(context).colorScheme.secondary,
          child: const Icon(Icons.add, color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildAnimatedQuotationCard(Map<String, dynamic> quote, int index) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(
          parent: _listAnimationController,
          curve: Interval(
            index * 0.1,
            1.0,
            curve: Curves.easeInOut,
          ),
        ),
      ),
      child: SlideTransition(
        position:
            Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero)
                .animate(
          CurvedAnimation(
            parent: _listAnimationController,
            curve: Interval(
              index * 0.1,
              1.0,
              curve: Curves.easeInOut,
            ),
          ),
        ),
        child: _buildQuotationCard(quote),
      ),
    );
  }

  Widget _buildQuotationCard(Map<String, dynamic> quote) {
    bool isOrdered = quote['status'] == 'Ordered';
    bool isPartiallyOrdered = quote['status'] == 'Partially Ordered';
    bool isOpen = quote['status'] == 'Open';
    bool isCancelled = quote['status'] == 'Cancelled';
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isOrdered
            ? const BorderSide(color: Color(0xFF4CAF50), width: 2)
            : isPartiallyOrdered
                ? const BorderSide(color: Color(0xFFFFA000), width: 2)
                : isOpen
                    ? const BorderSide(color: Color(0xFF2196F3), width: 2)
                    : isCancelled
                        ? const BorderSide(color: Color(0xFFF44336), width: 2)
                        : BorderSide.none,
      ),
      child: Container(
        padding: const EdgeInsets.all(12),
        color: isOrdered
            ? const Color(0xFFE8F5E9)
            : isPartiallyOrdered
                ? const Color(0xFFFFF3E0)
                : isOpen
                    ? const Color(0xFFE3F2FD)
                    : isCancelled
                        ? const Color(0xFFFEF1F0)
                        : Colors.white,
        child: ListTile(
          contentPadding: const EdgeInsets.all(12),
          title: Text(
            quote['name'] ?? 'Unnamed Quotation',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Color(0xFF003366),
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Customer: ${quote['customer_name'] ?? 'N/A'}',
                style: const TextStyle(color: Colors.grey),
              ),
              Text(
                'Date: ${quote['transaction_date'] ?? 'N/A'}',
                style: const TextStyle(color: Colors.grey),
              ),
              Text(
                'To: ${quote['quotation_to'] ?? 'N/A'}',
                style: const TextStyle(color: Colors.grey),
              ),
              Text(
                'Status: ${quote['status'] ?? 'N/A'}',
                style: TextStyle(
                  color: isOrdered
                      ? const Color(0xFF4CAF50)
                      : isPartiallyOrdered
                          ? const Color(0xFFFFA000)
                          : isOpen
                              ? const Color(0xFF2196F3)
                              : isCancelled
                                  ? const Color(0xFFF44336)
                                  : Colors.grey,
                  fontWeight:
                      isOrdered || isPartiallyOrdered || isOpen || isCancelled
                          ? FontWeight.bold
                          : FontWeight.normal,
                ),
              ),
            ],
          ),
          trailing: Icon(
            Icons.chevron_right,
            color: Theme.of(context).colorScheme.secondary,
          ),
          onTap: () {
            if (widget.sid.isEmpty) {
              showErrorDialog(context, 'Session Error',
                  'Invalid session. Please log in again.');
              Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
              return;
            }
            Navigator.pushNamed(
              context,
              '/quotation_detail',
              arguments: {
                'sid': widget.sid,
                'serverUrl': widget.serverUrl,
                ...quote, // Spread the quotation map to include all its fields
              },
            );
          },
        ),
      ),
    );
  }
}
