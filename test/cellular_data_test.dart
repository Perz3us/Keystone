import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/modules/noobwrt/cellular/cellular_data.dart';

void main() {
  test('cell_info keeps headings and grades bars', () {
    final e = CellEntry.parse({
      'modem_info': [
        {'key': 'NR5G-NSA', 'value': 'NR5G-NSA', 'type': 'plain_text'},
        {
          'key': 'RSRP',
          'value': '-85',
          'unit': 'dBm',
          'min_value': '-140',
          'max_value': '-44',
          'type': 'progress_bar',
        },
        {'key': 'CQI', 'value': '-'},
      ],
    });
    expect(e.length, 2);
    expect(e[0].isHeading, isTrue);
    expect(e[1].fill, closeTo(55 / 96, 1e-9));
    expect(e[1].isMain, isTrue);
    expect(const CellEntry('CQI', '12').isMain, isFalse);
  });

  test('current band lists CA and the NSA leg', () {
    final (mode, cells) = Carrier.parse({
      'current_band': {
        'status': 'ok',
        'network_mode': 'EN-DC',
        'cells': [
          {
            'role': 'pcc',
            'rat': 'LTE',
            'band_name': 'LTE B3',
            'channel': '1300',
            'channel_type': 'EARFCN',
            'pci': '123',
            'dl_bandwidth': '20',
            'scs': '',
          },
          {
            'role': 'scc',
            'rat': 'LTE',
            'band_name': 'LTE B1',
            'channel': '100',
            'pci': '7',
          },
          {
            'role': 'nsa',
            'rat': 'NR',
            'band_name': 'NR n78',
            'channel': '627264',
            'channel_type': 'NR-ARFCN',
            'pci': '293',
            'dl_bandwidth': '100',
            'scs': '30kHz',
          },
        ],
      },
    });
    expect(mode, 'EN-DC');
    expect(cells.map((c) => c.label), ['Primary', 'Aggregated', '5G (NSA)']);
    expect(cells[0].detail, 'LTE B3 · 20 MHz\nPCI 123  EARFCN 1300');
    expect(
      Carrier.parse({
        'current_band': {'status': 'not_registered'},
      }).$2,
      isEmpty,
    );
  });

  test('lockband reads classes and strips band name prefixes', () {
    final b = BandClass.parse({
      'lockband': {
        'LTE': {
          'available_band': [
            {'band_id': '1', 'band_name': 'LTE_B1'},
            {'band_id': '3', 'band_name': 'LTE_B3'},
          ],
          'lock_band': ['3'],
        },
        'NR_NSA': {
          'available_band': [
            {'band_id': '78', 'band_name': 'NSA_NR_N78'},
          ],
          'lock_band': [],
        },
        'UMTS': {'available_band': [], 'lock_band': []},
      },
    });
    expect(b.map((c) => c.title), ['4G', '5G NSA']);
    expect(b[0].available, [('1', 'B1'), ('3', 'B3')]);
    expect(b[0].locked, {'3'});
    expect(b[1].available.single.$2, 'N78');
  });

  test('neighbour cells and lock status', () {
    final l = CellLock.parse({
      'neighborcell': {
        'lockcell_status': {
          'LTE': 'locked',
          'LTE_Freq': '1300',
          'LTE_PCI': '123',
          'NR': 'unlock',
        },
        'LTE': [
          {'arfcn': '1300', 'pci': '124', 'rsrp': '-95', 'rsrq': '-11'},
        ],
        'NR': [],
      },
    });
    expect(l.lte, 'PCI 123 · EARFCN 1300');
    expect(l.nr, isNull);
    expect(l.locked, isTrue);
    expect(l.nearby.single.pci, '124');
  });

  test('5G Modem app bands and locks, as an RG500Q reports them', () {
    final j = FiveGBands.decode(
      '{ "celllock": "cell 1725 151", "celllock5g": "off", '
      '"supported": [ { "band": 1, "txt": "FDD 2100 MHz" }, '
      '{ "band": 3, "txt": "FDD 1800 MHz" } ], "enabled": [ 1, 3 ], '
      '"supported5gnsa": [ { "band": 78, "txt": "TDD 3500 MHz" } ], '
      '"enabled5gnsa": [ 78 ], "supported5gsa": [], "enabled5gsa": [] }',
    );
    final b = FiveGBands.classes(j);
    expect(b.map((c) => c.title), ['4G', '5G NSA']);
    expect(b[0].available, [('1', 'B1'), ('3', 'B3')]);
    expect(b[0].locked, {'1', '3'});
    expect(b[1].available.single, ('78', 'n78'));
    final l = FiveGBands.lock(j);
    expect(l.lte, 'PCI 151 · EARFCN 1725');
    expect(l.nr, isNull);
    expect(FiveGBands.lock(const {'celllock': 'off'}).locked, isFalse);
  });

  test('5G Modem app neighbours become lockable cells', () {
    final n = FiveGBands.nearby([
      {
        'band': '3',
        'earfcn': '1725',
        'pci': '151',
        'rsrp': '-96',
        'rsrq': '-10',
        'serving': true,
      },
      {'band': 'n78', 'earfcn': '627264', 'pci': '293', 'rsrp': '-101'},
      {'band': '1', 'earfcn': '-', 'pci': '64'},
    ]);
    expect(n.length, 2);
    expect(n[0].rat, 'LTE');
    expect(n[0].serving, isTrue);
    expect(n[1].rat, 'NR');
  });
}
