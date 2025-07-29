// lib/screens/quotation_detail_screen.dart
import 'dart:typed_data'; // For Uint8List
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show rootBundle; // For loading asset image
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart'; // For PdfColor
import 'package:http/http.dart' as http;
import 'package:home_mart/error_handler.dart'; // Import error handler

class QuotationDetailScreen extends StatelessWidget {
  final String serverUrl; // Added serverUrl to load images for PDF
  const QuotationDetailScreen({super.key, required this.serverUrl});

  @override
  Widget build(BuildContext context) {
    // Retrieve quotation data passed as arguments
    final Map quotation = ModalRoute.of(context)!.settings.arguments as Map;

    // Extract taxes from the quotation data
    final List<dynamic> taxes = quotation['taxes'] ?? [];
    final double totalTaxesAndCharges =
        quotation['total_taxes_and_charges']?.toDouble() ?? 0.0;

    return Scaffold(
      appBar: AppBar(
        title: Text(quotation['name'] ?? 'Quotation Details'),
        backgroundColor: Theme.of(context).primaryColor,
        actions: [
          IconButton(
            icon: const Icon(Icons.print, color: Colors.white),
            tooltip: 'Print Preview',
            onPressed: () => _showPrintPreview(context, quotation),
          ),
        ],
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
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // General Quotation Details Card
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    color: Colors.white,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Quotation Details',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const Divider(),
                        _buildDetailRow('Name', quotation['name'] ?? 'N/A'),
                        _buildDetailRow(
                          'Customer Name',
                          quotation['customer_name'] ?? 'N/A',
                        ),
                        _buildDetailRow(
                          'Contact Mobile',
                          quotation['contact_mobile'] ?? 'N/A',
                        ),
                        _buildDetailRow(
                          'Quotation To',
                          quotation['quotation_to'] ?? 'N/A',
                        ),
                        _buildDetailRow(
                          'Transaction Date',
                          quotation['transaction_date'] ?? 'N/A',
                        ),
                        _buildDetailRow(
                          'Valid Till',
                          quotation['valid_till'] ?? 'N/A',
                        ),
                        _buildDetailRow('Status', quotation['status'] ?? 'N/A'),
                        _buildDetailRow(
                          'Order Type',
                          quotation['order_type'] ?? 'N/A',
                        ),
                        _buildDetailRow(
                          'Sales Person',
                          quotation['sales_person'] ?? 'N/A',
                        ),
                        _buildDetailRow(
                          'Currency',
                          quotation['currency'] ?? 'N/A',
                        ),
                        _buildDetailRow(
                          'Company',
                          quotation['company'] ?? 'N/A',
                        ),
                        _buildDetailRow(
                          'Conversion Rate',
                          quotation['conversion_rate']?.toString() ?? 'N/A',
                        ),
                        _buildDetailRow(
                          'Selling Price List',
                          quotation['selling_price_list'] ?? 'N/A',
                        ),
                        _buildDetailRow(
                          'Price List Currency',
                          quotation['price_list_currency'] ?? 'N/A',
                        ),
                        _buildDetailRow(
                          'PLC Conversion Rate',
                          quotation['plc_conversion_rate']?.toString() ?? 'N/A',
                        ),
                        _buildDetailRow(
                          'GST Category',
                          quotation['gst_category']?.toString() ?? 'N/A',
                        ), // New field
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                // Items Details Card
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    color: Colors.white,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Items',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF003366),
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (quotation['items'] != null &&
                            (quotation['items'] as List).isNotEmpty)
                          ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: (quotation['items'] as List).length,
                            itemBuilder: (context, index) {
                              final item = quotation['items'][index];
                              return Card(
                                elevation: 1,
                                color: Colors.white,
                                margin: const EdgeInsets.only(bottom: 8),
                                child: Padding(
                                  padding: const EdgeInsets.all(12.0),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item['item_name'] ?? 'Unnamed Item',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF003366),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      _buildItemDetailRow(
                                        'Quantity',
                                        '${item['qty'] ?? 'N/A'} ${item['uom'] ?? ''}',
                                      ),
                                      _buildItemDetailRow(
                                        'Rate',
                                        item['rate']?.toStringAsFixed(2) ??
                                            'N/A',
                                      ),
                                      _buildItemDetailRow(
                                        'Discount Percentage',
                                        item['discount_percentage']
                                                ?.toStringAsFixed(2) ??
                                            'N/A',
                                      ),
                                      _buildItemDetailRow(
                                        'Discount Amount',
                                        item['discount_amount']
                                                ?.toStringAsFixed(2) ??
                                            'N/A',
                                      ),
                                      _buildItemDetailRow(
                                        'Amount',
                                        item['amount']?.toStringAsFixed(2) ??
                                            'N/A',
                                      ),
                                      _buildItemDetailRow(
                                        'Conversion Factor',
                                        item['conversion_factor'] ?? 'N/A',
                                      ),
                                      if (item['item_tax_rate'] != null &&
                                          item['item_tax_rate']
                                              .toString()
                                              .isNotEmpty)
                                        _buildItemDetailRow(
                                          'Item Tax Rate',
                                          item['item_tax_rate'].toString(),
                                        ), // Display item tax rate
                                    ],
                                  ),
                                ),
                              );
                            },
                          )
                        else
                          const Text(
                            'No items available',
                            style: TextStyle(color: Color(0xFF003366)),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                // NEW: Sales Taxes and Charges Card
                if (taxes.isNotEmpty || totalTaxesAndCharges > 0)
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      color: Colors.white,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Taxes and Charges',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF003366),
                            ),
                          ),
                          const SizedBox(height: 10),
                          if (taxes.isNotEmpty)
                            ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: taxes.length,
                              itemBuilder: (context, index) {
                                final tax = taxes[index];
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8.0),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _buildItemDetailRow(
                                        'Description',
                                        tax['description'] ?? 'N/A',
                                      ),
                                      _buildItemDetailRow(
                                        'Type',
                                        tax['charge_type'] ?? 'N/A',
                                      ),
                                      _buildItemDetailRow(
                                        'Amount',
                                        tax['tax_amount']?.toStringAsFixed(2) ??
                                            '0.00',
                                      ),
                                    ],
                                  ),
                                );
                              },
                            )
                          else
                            const Text(
                              'No specific tax breakdown available for this quotation.',
                              style: TextStyle(color: Color(0xFF003366)),
                            ),
                          const Divider(),
                          _buildDetailRow(
                            'Total Taxes & Charges',
                            totalTaxesAndCharges.toStringAsFixed(2),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Helper widget to build a row for general quotation details
  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label: ',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Color(0xFF003366),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 16, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  // Helper widget to build a row for item details
  Widget _buildItemDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label: ',
            style: const TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 14,
              color: Color(0xFF424242),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14, color: Colors.black54),
            ),
          ),
        ],
      ),
    );
  }

  // Show PDF print preview dialog
  void _showPrintPreview(BuildContext context, Map quotation) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(10),
        child: SizedBox(
          width: MediaQuery.of(context).size.width * 0.9,
          height: MediaQuery.of(context).size.height * 0.8,
          child: PdfPreview(
            build: (format) => _generatePdf(quotation),
            canChangePageFormat: false,
            canDebug: false,
            initialPageFormat: PdfPageFormat.a4,
            allowSharing: true, // Allow sharing the generated PDF
            allowPrinting: true, // Allow printing the generated PDF
          ),
        ),
      ),
    );
  }

  // Convert number to words in Indian numbering system
  String _numberToWordsIndian(int number) {
    if (number == 0) return 'Zero';
    const List units = [
      '',
      'One',
      'Two',
      'Three',
      'Four',
      'Five',
      'Six',
      'Seven',
      'Eight',
      'Nine',
      'Ten',
      'Eleven',
      'Twelve',
      'Thirteen',
      'Fourteen',
      'Fifteen',
      'Sixteen',
      'Seventeen',
      'Eighteen',
      'Nineteen',
    ];
    const List tens = [
      '',
      '',
      'Twenty',
      'Thirty',
      'Forty',
      'Fifty',
      'Sixty',
      'Seventy',
      'Eighty',
      'Ninety',
    ];
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
    if (crore > 0) parts.add(_convertLessThanThousand(crore) + ' Crore');
    if (lakh > 0) parts.add(_convertLessThanThousand(lakh) + ' Lakh');
    if (thousand > 0)
      parts.add(_convertLessThanThousand(thousand) + ' Thousand');
    if (hundred > 0) parts.add('${units[hundred]} Hundred');
    if (remaining > 0) {
      if (hundred > 0 || thousand > 0 || lakh > 0 || crore > 0)
        parts.add('and');
      parts.add(_convertLessThanThousand(remaining));
    }
    return parts.join(' ').trim();
  }

  // Helper for _numberToWordsIndian to convert numbers less than one thousand
  String _convertLessThanThousand(int number) {
    const List units = [
      '',
      'One',
      'Two',
      'Three',
      'Four',
      'Five',
      'Six',
      'Seven',
      'Eight',
      'Nine',
      'Ten',
      'Eleven',
      'Twelve',
      'Thirteen',
      'Fourteen',
      'Fifteen',
      'Sixteen',
      'Seventeen',
      'Eighteen',
      'Nineteen',
    ];
    const List tens = [
      '',
      '',
      'Twenty',
      'Thirty',
      'Forty',
      'Fifty',
      'Sixty',
      'Seventy',
      'Eighty',
      'Ninety',
    ];
    if (number == 0) return '';
    if (number < 20) return units[number];
    int ten = number ~/ 10;
    int unit = number % 10;
    return '${tens[ten]}${unit > 0 ? ' ${units[unit]}' : ''}'.trim();
  }

  // Split text into lines to fit PDF layout
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

  // Generate the PDF document for quotation
  Future<Uint8List> _generatePdf(Map quotation) async {
    final pdf = pw.Document();
    pw.Font? font;
    try {
      font = await PdfGoogleFonts.notoSansRegular(); // Try loading Google Font
    } catch (e) {
      debugPrint('Error loading font: $e');
      font = pw.Font.helvetica(); // Fallback to Helvetica
    }

    // Load company logo
    final Uint8List logoData = (await rootBundle.load(
      'assets/images/logo.jpg',
    )).buffer.asUint8List();
    final pw.MemoryImage logoImage = pw.MemoryImage(logoData);

    // Calculate totals for PDF
    double total =
        quotation['items']?.fold(
          0.0,
          (sum, item) => sum + (item['amount']?.toDouble() ?? 0.0),
        ) ??
        0.0;
    // Use total_taxes_and_charges from the main quotation object if available, otherwise 0.0
    double totalTaxesAndCharges =
        quotation['total_taxes_and_charges']?.toDouble() ?? 0.0;

    int totalQty =
        quotation['items']?.fold(
          0,
          (sum, item) => sum + (item['qty']?.toInt() ?? 0),
        ) ??
        0;
    double grandTotal =
        total +
        totalTaxesAndCharges; // Grand total includes items + total taxes
    int roundedTotal = grandTotal
        .round(); // Round the grand total for words conversion
    String inWords = 'INR ${_numberToWordsIndian(roundedTotal)} only';

    // Prepare text lines for PDF to handle long strings
    List<String> customerNameLines = _splitTextIntoLines(
      quotation['customer_name'] ?? 'N/A',
      25,
    );
    List<String> mobileNoLines = _splitTextIntoLines(
      quotation['contact_mobile'] ?? 'N/A',
      25,
    );
    List<String> dateLines = _splitTextIntoLines(
      quotation['transaction_date'] ??
          DateFormat('dd-MM-yyyy').format(DateTime.now()),
      25,
    );
    List<String> validTillLines = _splitTextIntoLines(
      quotation['valid_till'] ??
          DateFormat(
            'dd-MM-yyyy',
          ).format(DateTime.now().add(const Duration(days: 30))),
      25,
    );
    List<String> userNameLines = _splitTextIntoLines(
      quotation['owner'] ?? 'N/A',
      25,
    ); // Using 'owner' as user name
    List<String> salesPersonLines = _splitTextIntoLines(
      quotation['sales_person'] ?? 'N/A',
      25,
    );
    List<String> remarksLines = _splitTextIntoLines(
      quotation['remarks'] ?? 'N/A',
      25,
    );
    List<String> inWordsLines = _splitTextIntoLines(inWords, 50);
    List<String> quoteNoLines = _splitTextIntoLines(
      quotation['name'] ?? 'N/A',
      25,
    );
    List<String> gstCategoryLines = _splitTextIntoLines(
      quotation['gst_category']?.toString() ?? 'N/A',
      25,
    ); // New line for GST Category

    bool showSalesPerson =
        (quotation['sales_person'] != null &&
        quotation['sales_person'].toString().isNotEmpty &&
        quotation['sales_person'] != 'N/A');
    bool showRemarks =
        (quotation['remarks'] != null &&
        quotation['remarks'].toString().isNotEmpty &&
        quotation['remarks'] != 'N/A');
    final List<dynamic> taxesList =
        quotation['taxes'] ?? []; // Extract taxes for PDF

    // Load item images for PDF
    List<pw.MemoryImage?> itemImages = [];
    if (quotation['items'] != null && (quotation['items'] as List).isNotEmpty) {
      for (var item in quotation['items']) {
        if (item['image'] != null && item['image'].isNotEmpty) {
          try {
            final response = await http.get(
              Uri.parse(
                item['image'].startsWith('http')
                    ? item['image']
                    : '$serverUrl${item['image']}',
              ),
            ); // Use serverUrl from widget
            if (response.statusCode == 200) {
              final imageData = response.bodyBytes;
              itemImages.add(pw.MemoryImage(imageData));
            } else {
              itemImages.add(null); // Add null if image fetch fails
              debugPrint(
                'Failed to load image for PDF: ${item['item_name']} - Status: ${response.statusCode}',
              );
            }
          } catch (e) {
            debugPrint(
              'Error loading image for ${item['item_name']} for PDF: $e',
            );
            itemImages.add(null); // Add null on exception
          }
        } else {
          itemImages.add(null); // Add null if no image path
        }
      }
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(56.7), // Standard A4 margins (2cm)
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Image(logoImage, width: 50, height: 50), // Company logo
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Text(
                      'QUOTATION',
                      style: pw.TextStyle(
                        fontSize: 18,
                        fontWeight: pw.FontWeight.bold,
                        font: font,
                      ),
                    ),
                    pw.Text(
                      'HOME MART', // Your company name
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                        font: font,
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(width: 50), // Spacer to balance header layout
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Divider(thickness: 1, color: PdfColors.black), // Separator line
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
                    // Customer Name
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.start,
                      children: [
                        pw.Text(
                          'Customer Name:',
                          style: pw.TextStyle(fontSize: 12, font: font),
                        ),
                        pw.SizedBox(width: 5),
                        pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: customerNameLines
                              .map(
                                (line) => pw.Text(
                                  line,
                                  style: pw.TextStyle(fontSize: 12, font: font),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 10),
                    // Mobile Number
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.start,
                      children: [
                        pw.Text(
                          'Mobile No:',
                          style: pw.TextStyle(fontSize: 12, font: font),
                        ),
                        pw.SizedBox(width: 5),
                        pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: mobileNoLines
                              .map(
                                (line) => pw.Text(
                                  line,
                                  style: pw.TextStyle(fontSize: 12, font: font),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 10),
                    // GST Category
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.start,
                      children: [
                        pw.Text(
                          'GST Category:',
                          style: pw.TextStyle(fontSize: 12, font: font),
                        ),
                        pw.SizedBox(width: 5),
                        pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: gstCategoryLines
                              .map(
                                (line) => pw.Text(
                                  line,
                                  style: pw.TextStyle(fontSize: 12, font: font),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              pw.Expanded(
                flex: 1,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    // Quotation Number
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.start,
                      children: [
                        pw.Text(
                          'Quote No.:',
                          style: pw.TextStyle(fontSize: 12, font: font),
                        ),
                        pw.SizedBox(width: 5),
                        pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: quoteNoLines
                              .map(
                                (line) => pw.Text(
                                  line,
                                  style: pw.TextStyle(fontSize: 12, font: font),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 10),
                    // Date
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.start,
                      children: [
                        pw.Text(
                          'Date:',
                          style: pw.TextStyle(fontSize: 12, font: font),
                        ),
                        pw.SizedBox(width: 5),
                        pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: dateLines
                              .map(
                                (line) => pw.Text(
                                  line,
                                  style: pw.TextStyle(fontSize: 12, font: font),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 10),
                    // Valid Till
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.start,
                      children: [
                        pw.Text(
                          'Valid Till:',
                          style: pw.TextStyle(fontSize: 12, font: font),
                        ),
                        pw.SizedBox(width: 5),
                        pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: validTillLines
                              .map(
                                (line) => pw.Text(
                                  line,
                                  style: pw.TextStyle(fontSize: 12, font: font),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 10),
                    // User Name (Owner)
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.start,
                      children: [
                        pw.Text(
                          'User Name:',
                          style: pw.TextStyle(fontSize: 12, font: font),
                        ),
                        pw.SizedBox(width: 5),
                        pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: userNameLines
                              .map(
                                (line) => pw.Text(
                                  line,
                                  style: pw.TextStyle(fontSize: 12, font: font),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ),
                    // Sales Person (conditionally shown)
                    if (showSalesPerson) ...[
                      pw.SizedBox(height: 10),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.start,
                        children: [
                          pw.Text(
                            'Sales Person:',
                            style: pw.TextStyle(fontSize: 12, font: font),
                          ),
                          pw.SizedBox(width: 5),
                          pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: salesPersonLines
                                .map(
                                  (line) => pw.Text(
                                    line,
                                    style: pw.TextStyle(
                                      fontSize: 12,
                                      font: font,
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ],
                      ),
                    ],
                    // Remarks (conditionally shown)
                    if (showRemarks) ...[
                      pw.SizedBox(height: 10),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.start,
                        children: [
                          pw.Text(
                            'Remarks:',
                            style: pw.TextStyle(fontSize: 12, font: font),
                          ),
                          pw.SizedBox(width: 5),
                          pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: remarksLines
                                .map(
                                  (line) => pw.Text(
                                    line,
                                    style: pw.TextStyle(
                                      fontSize: 12,
                                      font: font,
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 20),
          pw.Text(
            'Items',
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
              font: font,
            ),
          ),
          pw.SizedBox(height: 10),
          // Items Table
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.black),
            columnWidths: {
              0: const pw.FixedColumnWidth(20), // Sr
              1: const pw.FixedColumnWidth(100), // Item Name
              2: const pw.FixedColumnWidth(40), // Image
              3: const pw.FixedColumnWidth(60), // Qty/UOM (combined)
              4: const pw.FixedColumnWidth(60), // List Rate
              5: const pw.FixedColumnWidth(60), // After Disc
              6: const pw.FixedColumnWidth(60), // Amount
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  pw.Container(
                    alignment: pw.Alignment.center,
                    padding: const pw.EdgeInsets.all(5),
                    child: pw.Text(
                      'Sr',
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 10,
                        font: font,
                      ),
                    ),
                  ),
                  pw.Container(
                    alignment: pw.Alignment.center,
                    padding: const pw.EdgeInsets.all(5),
                    child: pw.Text(
                      'Item Name',
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 10,
                        font: font,
                      ),
                    ),
                  ),
                  pw.Container(
                    alignment: pw.Alignment.center,
                    padding: const pw.EdgeInsets.all(5),
                    child: pw.Text(
                      'Image',
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 10,
                        font: font,
                      ),
                    ),
                  ),
                  pw.Container(
                    alignment: pw.Alignment.center,
                    padding: const pw.EdgeInsets.all(5),
                    child: pw.Text(
                      'Qty/UOM',
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 10,
                        font: font,
                      ),
                    ),
                  ),
                  pw.Container(
                    alignment: pw.Alignment.center,
                    padding: const pw.EdgeInsets.all(5),
                    child: pw.Text(
                      'List Rate',
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 10,
                        font: font,
                      ),
                    ),
                  ),
                  pw.Container(
                    alignment: pw.Alignment.center,
                    padding: const pw.EdgeInsets.all(5),
                    child: pw.Text(
                      'After Disc',
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 10,
                        font: font,
                      ),
                    ),
                  ),
                  pw.Container(
                    alignment: pw.Alignment.center,
                    padding: const pw.EdgeInsets.all(5),
                    child: pw.Text(
                      'Amount',
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 10,
                        font: font,
                      ),
                    ),
                  ),
                ],
              ),
              if (quotation['items'] != null &&
                  (quotation['items'] as List).isNotEmpty)
                ...List.generate((quotation['items'] as List).length, (index) {
                  final item = quotation['items'][index];
                  final mrp = item['price_list_rate']?.toDouble() ?? 0.0;
                  final afterDisc = item['rate']?.toDouble() ?? 0.0;
                  final amount = item['amount']?.toDouble() ?? 0.0;
                  final qtyUom =
                      '${item['qty']?.toString() ?? 'N/A'}/${item['uom'] ?? 'N/A'}';
                  return pw.TableRow(
                    children: [
                      pw.Container(
                        alignment: pw.Alignment.center,
                        padding: const pw.EdgeInsets.all(5),
                        child: pw.Text(
                          '${index + 1}',
                          style: pw.TextStyle(fontSize: 10, font: font),
                        ),
                      ),
                      pw.Container(
                        alignment: pw.Alignment.centerLeft,
                        padding: const pw.EdgeInsets.all(5),
                        child: pw.Text(
                          item['item_name'] ?? 'N/A',
                          style: pw.TextStyle(fontSize: 10, font: font),
                        ),
                      ),
                      pw.Container(
                        alignment: pw.Alignment.center,
                        padding: const pw.EdgeInsets.all(5),
                        child: itemImages[index] != null
                            ? pw.Image(
                                itemImages[index]!,
                                width: 30,
                                height: 30,
                                fit: pw.BoxFit.cover,
                              )
                            : pw.SizedBox(
                                width: 30,
                                height: 30,
                              ), // Placeholder for no image
                      ),
                      pw.Container(
                        alignment: pw.Alignment.center,
                        padding: const pw.EdgeInsets.all(5),
                        child: pw.Text(
                          qtyUom,
                          style: pw.TextStyle(fontSize: 10, font: font),
                        ),
                      ),
                      pw.Container(
                        alignment: pw.Alignment.center,
                        padding: const pw.EdgeInsets.all(5),
                        child: pw.Text(
                          mrp.toStringAsFixed(2),
                          style: pw.TextStyle(fontSize: 10, font: font),
                        ),
                      ),
                      pw.Container(
                        alignment: pw.Alignment.center,
                        padding: const pw.EdgeInsets.all(5),
                        child: pw.Text(
                          afterDisc.toStringAsFixed(2),
                          style: pw.TextStyle(fontSize: 10, font: font),
                        ),
                      ),
                      pw.Container(
                        alignment: pw.Alignment.center,
                        padding: const pw.EdgeInsets.all(5),
                        child: pw.Text(
                          amount.toStringAsFixed(2),
                          style: pw.TextStyle(fontSize: 10, font: font),
                        ),
                      ),
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
                      child: pw.Text(
                        'No items available',
                        style: pw.TextStyle(fontSize: 10, font: font),
                      ),
                    ),
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
          // NEW: Taxes and Charges Table (if taxes are present)
          if (taxesList.isNotEmpty || totalTaxesAndCharges > 0)
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Taxes and Charges',
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                    font: font,
                  ),
                ),
                pw.SizedBox(height: 10),
                if (taxesList.isNotEmpty)
                  pw.Table(
                    border: pw.TableBorder.all(color: PdfColors.black),
                    columnWidths: {
                      0: const pw.FixedColumnWidth(150), // Description
                      1: const pw.FixedColumnWidth(100), // Type
                      2: const pw.FixedColumnWidth(100), // Amount
                    },
                    children: [
                      pw.TableRow(
                        decoration: const pw.BoxDecoration(
                          color: PdfColors.grey200,
                        ),
                        children: [
                          pw.Container(
                            alignment: pw.Alignment.center,
                            padding: const pw.EdgeInsets.all(5),
                            child: pw.Text(
                              'Description',
                              style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                                fontSize: 10,
                                font: font,
                              ),
                            ),
                          ),
                          pw.Container(
                            alignment: pw.Alignment.center,
                            padding: const pw.EdgeInsets.all(5),
                            child: pw.Text(
                              'Charge Type',
                              style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                                fontSize: 10,
                                font: font,
                              ),
                            ),
                          ),
                          pw.Container(
                            alignment: pw.Alignment.center,
                            padding: const pw.EdgeInsets.all(5),
                            child: pw.Text(
                              'Tax Amount',
                              style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                                fontSize: 10,
                                font: font,
                              ),
                            ),
                          ),
                        ],
                      ),
                      ...taxesList.map((tax) {
                        return pw.TableRow(
                          children: [
                            pw.Container(
                              alignment: pw.Alignment.centerLeft,
                              padding: const pw.EdgeInsets.all(5),
                              child: pw.Text(
                                tax['description'] ?? 'N/A',
                                style: pw.TextStyle(fontSize: 10, font: font),
                              ),
                            ),
                            pw.Container(
                              alignment: pw.Alignment.center,
                              padding: const pw.EdgeInsets.all(5),
                              child: pw.Text(
                                tax['charge_type'] ?? 'N/A',
                                style: pw.TextStyle(fontSize: 10, font: font),
                              ),
                            ),
                            pw.Container(
                              alignment: pw.Alignment.centerRight,
                              padding: const pw.EdgeInsets.all(5),
                              child: pw.Text(
                                (tax['tax_amount']?.toDouble() ?? 0.0)
                                    .toStringAsFixed(2),
                                style: pw.TextStyle(fontSize: 10, font: font),
                              ),
                            ),
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
                pw.SizedBox(height: 10),
                pw.Align(
                  alignment: pw.Alignment.centerRight,
                  child: pw.Text(
                    'Total Taxes and Charges: ₹${totalTaxesAndCharges.toStringAsFixed(2)}',
                    style: pw.TextStyle(
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                      font: font,
                    ),
                  ),
                ),
              ],
            ),
          pw.SizedBox(height: 20),
          // Totals and Grand Totals
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                flex: 1,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Row(
                      children: [
                        pw.Text(
                          'Total Quantity:',
                          style: pw.TextStyle(
                            fontSize: 12,
                            fontWeight: pw.FontWeight.bold,
                            font: font,
                          ),
                        ),
                        pw.SizedBox(width: 10),
                        pw.Text(
                          '$totalQty',
                          style: pw.TextStyle(fontSize: 12, font: font),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              pw.Expanded(
                flex: 1,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          'Total (Items):',
                          style: pw.TextStyle(fontSize: 12, font: font),
                        ),
                        pw.Text(
                          '₹${total.toStringAsFixed(2)}',
                          style: pw.TextStyle(fontSize: 12, font: font),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 10),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          'Grand Total:',
                          style: pw.TextStyle(fontSize: 12, font: font),
                        ),
                        pw.Text(
                          '₹${grandTotal.toStringAsFixed(2)}',
                          style: pw.TextStyle(fontSize: 12, font: font),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 10),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          'Rounded Total:',
                          style: pw.TextStyle(fontSize: 12, font: font),
                        ),
                        pw.Text(
                          '₹${roundedTotal.toStringAsFixed(2)}',
                          style: pw.TextStyle(fontSize: 12, font: font),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 10),
          // Amount in Words
          pw.Row(
            children: [
              pw.Expanded(
                flex: 1,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'In Words:',
                      style: pw.TextStyle(fontSize: 12, font: font),
                    ),
                    ...inWordsLines.map(
                      (line) => pw.Text(
                        line,
                        style: pw.TextStyle(fontSize: 12, font: font),
                      ),
                    ),
                  ],
                ),
              ),
              pw.Expanded(flex: 1, child: pw.SizedBox()),
            ],
          ),
          pw.SizedBox(height: 60),
          // Signatures
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Container(
                    width: 150,
                    child: pw.Divider(thickness: 1, color: PdfColors.black),
                  ),
                  pw.Text(
                    'Customer\'s Signature',
                    style: pw.TextStyle(
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                      font: font,
                    ),
                  ),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Container(
                    width: 150,
                    child: pw.Divider(thickness: 1, color: PdfColors.black),
                  ),
                  pw.Text(
                    'Authorized Signature',
                    style: pw.TextStyle(
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                      font: font,
                    ),
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
}
