// lib/screens/quotation_list_screen.dart
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:home_mart/error_handler.dart'; // Import error handler

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
  ScrollController _scrollController = ScrollController();

  late AnimationController _listAnimationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _loadQuotations();
    _searchController.addListener(_onSearchChanged);
    _scrollController.addListener(_onScroll);

    // Initialize animation controller for list items
    _listAnimationController = AnimationController(
      duration: const Duration(
        milliseconds: 500,
      ), // Shorter duration for quick, smooth fade
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _listAnimationController,
      curve: Curves.easeInOut, // Smooth easing curve for natural animation
    );
    _listAnimationController
        .forward(); // Start the animation when the screen loads
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
          // UPDATED API ENDPOINT as requested
          '${widget.serverUrl}/api/method/custom_scripts.API.qtn.get_quotation_details1?page=$_page&limit=$_pageSize',
        ),
        headers: _getHeaders(),
      );

      debugPrint('Response Status: ${response.statusCode}');
      debugPrint('Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        final List<dynamic> data =
            jsonResponse['data'] ?? jsonResponse['message'] ?? [];

        setState(() {
          if (isRefresh) {
            _quotations = data;
          } else {
            _quotations.addAll(data);
          }
          _filterQuotations(); // Re-filter after loading new data
          _page++;
          _hasMore =
              data.length == _pageSize; // If less than pageSize, no more data
          _isLoading = false;
        });

        // Cache the response (optional, can be expanded with proper cache management)
        _cachedData = {'data': _quotations, 'timestamp': DateTime.now()};
      } else {
        showApiErrorDialog(
          context,
          statusCode: response.statusCode,
          message: response.body,
        );
        setState(() => _isLoading = false);
      }
    } catch (e) {
      showErrorDialog(context, 'Network Error', 'Error loading quotations: $e');
      setState(() => _isLoading = false);
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels ==
            _scrollController.position.maxScrollExtent &&
        !_isLoading) {
      _loadQuotations(); // Load next page when scrolled to bottom
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
    final isSmallScreen = screenWidth < 400; // For 4" screens (~320-400px)

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
              padding: EdgeInsets.all(
                isSmallScreen ? 12.0 : 16.0,
              ), // Adjusted padding for responsiveness
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
                        padding: EdgeInsets.all(
                          isSmallScreen ? 12.0 : 16.0,
                        ), // Adjusted padding for responsiveness
                        itemCount:
                            _filteredQuotations.length +
                            (_hasMore ? 1 : 0), // Add 1 for loading indicator
                        separatorBuilder: (_, __) => SizedBox(
                          height: isSmallScreen ? 6 : 8,
                        ), // Runtime value
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
                          return _buildAnimatedQuotationCard(
                            quote,
                            index,
                          ); // Use animated card
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: ScaleTransition(
        scale: _fadeAnimation, // Use the same animation for FAB
        child: FloatingActionButton(
          onPressed: () async {
            // Navigate to quotation creation screen and pass SID
            await Navigator.pushNamed(
              context,
              '/quotation',
              arguments: {'sid': widget.sid, 'serverUrl': widget.serverUrl},
            );
            _loadQuotations(isRefresh: true); // Refresh list after returning
          },
          backgroundColor: Theme.of(context).colorScheme.secondary, // Teal
          child: const Icon(Icons.add, color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildAnimatedQuotationCard(Map<String, dynamic> quote, int index) {
    // Animate each card with a staggered fade effect based on index
    return FadeTransition(
      opacity: Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(
          parent: _listAnimationController,
          curve: Interval(
            index * 0.1, // Stagger the animation by 0.1 seconds per item
            1.0,
            curve: Curves.easeInOut,
          ),
        ),
      ),
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero)
            .animate(
              CurvedAnimation(
                parent: _listAnimationController,
                curve: Interval(
                  index * 0.1, // Stagger the animation by 0.1 seconds per item
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
    // Check if status is one of the specified values for highlighting
    bool isOrdered = quote['status'] == 'Ordered';
    bool isPartiallyOrdered = quote['status'] == 'Partially Ordered';
    bool isOpen = quote['status'] == 'Open';
    bool isCancelled = quote['status'] == 'Cancelled';

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        // Add a border based on status
        side: isOrdered
            ? const BorderSide(
                color: Color(0xFF4CAF50),
                width: 2,
              ) // Green border for "Ordered"
            : isPartiallyOrdered
            ? const BorderSide(
                color: Color(0xFFFFA000),
                width: 2,
              ) // Amber/orange border for "Partially Ordered"
            : isOpen
            ? const BorderSide(
                color: Color(0xFF2196F3),
                width: 2,
              ) // Blue border for "Open"
            : isCancelled
            ? const BorderSide(
                color: Color(0xFFF44336),
                width: 2,
              ) // Red border for "Cancelled"
            : BorderSide.none,
      ),
      child: Container(
        padding: const EdgeInsets.all(12),
        // Highlight background based on status
        color: isOrdered
            ? const Color(0xFFE8F5E9) // Light green for "Ordered"
            : isPartiallyOrdered
            ? const Color(0xFFFFF3E0) // Light amber for "Partially Ordered"
            : isOpen
            ? const Color(0xFFE3F2FD) // Light blue for "Open"
            : isCancelled
            ? const Color(0xFFFEF1F0) // Light red for "Cancelled"
            : Colors.white, // White for other statuses
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
              // Display status in subtitle with color based on status
              Text(
                'Status: ${quote['status'] ?? 'N/A'}',
                style: TextStyle(
                  color: isOrdered
                      ? const Color(0xFF4CAF50) // Green text for "Ordered"
                      : isPartiallyOrdered
                      ? const Color(
                          0xFFFFA000,
                        ) // Amber/orange text for "Partially Ordered"
                      : isOpen
                      ? const Color(0xFF2196F3) // Blue text for "Open"
                      : isCancelled
                      ? const Color(0xFFF44336) // Red text for "Cancelled"
                      : Colors.grey, // Grey text for other statuses
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
            Navigator.pushNamed(
              context,
              '/quotation_detail',
              arguments: quote, // Pass the entire quotation map
            );
          },
        ),
      ),
    );
  }
}
