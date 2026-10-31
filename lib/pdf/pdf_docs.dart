import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import '../config.dart';
import '../models.dart';

// The built-in PDF font has no rupee sign, so PDFs use "Rs.".
String _rs(num v) => 'Rs. ${NumberFormat.decimalPattern('en_IN').format(v)}';

pw.Widget _cell(String t, {bool bold = false, pw.TextAlign align = pw.TextAlign.left}) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
    child: pw.Text(t, textAlign: align, style: pw.TextStyle(fontSize: 11, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)));

pw.Widget _header(String title) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text(AppConfig.schoolName, style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 2),
      pw.Text(title, style: const pw.TextStyle(fontSize: 13, color: PdfColors.grey700)),
      pw.Divider(),
    ]);

Future<void> _saveAndShare(pw.Document doc, String name, String subject) async {
  final dir = await getTemporaryDirectory();
  final f = File('${dir.path}/$name');
  await f.writeAsBytes(await doc.save());
  await Share.shareXFiles([XFile(f.path)], subject: subject);
}

String _safe(String s) => s.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');

/// Fee receipt for one payment. [account] is the JSON returned by the `fee_account` function.
Future<void> shareReceipt(Map<String, dynamic> account, Map<String, dynamic> payment) async {
  final st = Map<String, dynamic>.from(account['student'] as Map);
  final doc = pw.Document();
  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.a5,
    build: (c) => pw.Padding(padding: const pw.EdgeInsets.all(18), child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      _header('FEE RECEIPT'),
      pw.Table(border: pw.TableBorder.all(color: PdfColors.grey500), columnWidths: {0: const pw.FlexColumnWidth(2), 1: const pw.FlexColumnWidth(3)}, children: [
        for (final r in [
          ['Receipt / reference no.', '${payment['reference_no']}'],
          ['Date of payment', DateFormat('d MMM yyyy').format(DateTime.parse(payment['paid_on'] as String))],
          ['Student', '${st['name']}'],
          ['Roll number', '${st['roll_no']}'],
          ['Class', yearName(st['year_level'] as int)],
          ['Academic year', '${account['year_label']}'],
          ['Amount received', _rs(n(payment['amount']))],
          ['Received by', '${payment['received_by']}'],
        ]) pw.TableRow(children: [_cell(r[0], bold: true), _cell(r[1])]),
      ]),
      pw.SizedBox(height: 12),
      pw.Text('Account position on ${DateFormat('d MMM yyyy').format(DateTime.now())}', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
      pw.Text('Total fees ${_rs(n(account['total']))}   |   Paid ${_rs(n(account['paid']))}   |   Remaining ${_rs(n(account['remaining']))}', style: const pw.TextStyle(fontSize: 10)),
      pw.Spacer(),
      pw.Text('Computer-generated receipt.', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
    ])),
  ));
  await _saveAndShare(doc, 'receipt_${_safe('${payment['reference_no']}')}.pdf', 'Fee receipt');
}

/// Report card for one examination. [result] is one element of `my_results`.
Future<void> shareReportCard(String studentName, int yearLevel, String rollNo, Map<String, dynamic> result) async {
  final subjects = (result['subjects'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  final passed = result['passed'] == true;
  final doc = pw.Document();
  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    build: (c) => pw.Padding(padding: const pw.EdgeInsets.all(24), child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      _header('REPORT CARD - ${result['exam_name']}'),
      pw.Text('Student: $studentName', style: const pw.TextStyle(fontSize: 12)),
      pw.Text('${yearName(yearLevel)}   |   Roll no. $rollNo', style: const pw.TextStyle(fontSize: 12)),
      pw.SizedBox(height: 14),
      pw.Table(border: pw.TableBorder.all(color: PdfColors.grey500), columnWidths: {0: const pw.FlexColumnWidth(3), 1: const pw.FlexColumnWidth(2), 2: const pw.FlexColumnWidth(2), 3: const pw.FlexColumnWidth(2)}, children: [
        pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColors.grey300), children: [_cell('Subject', bold: true), _cell('Marks', bold: true), _cell('Maximum', bold: true), _cell('%', bold: true)]),
        for (final s in subjects) pw.TableRow(children: [_cell('${s['subject']}'), _cell('${_trim(s['obtained'])}'), _cell('${_trim(s['max'])}'), _cell('${n(s['percentage']).toStringAsFixed(2)}')]),
        pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColors.grey200), children: [_cell('Total', bold: true), _cell('${_trim(result['total_obtained'])}', bold: true), _cell('${_trim(result['total_max'])}', bold: true), _cell('${n(result['percentage']).toStringAsFixed(2)}', bold: true)]),
      ]),
      pw.SizedBox(height: 12),
      pw.Text('Overall percentage: ${n(result['percentage']).toStringAsFixed(2)}%', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
      if (result['rank'] != null) pw.Text('Class rank: ${result['rank']} of ${result['ranked_students']}', style: const pw.TextStyle(fontSize: 12)),
      pw.Text('Result: ${passed ? 'PASS' : 'FAIL'}', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
      pw.Spacer(),
      pw.Text('Generated ${DateFormat('d MMM yyyy').format(DateTime.now())} from verified, published marks.', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
    ])),
  ));
  await _saveAndShare(doc, 'report_card_${_safe('${result['exam_name']}')}.pdf', 'Report card');
}

String _trim(dynamic v) {
  final d = n(v).toDouble();
  return d == d.roundToDouble() ? d.toInt().toString() : d.toString();
}
