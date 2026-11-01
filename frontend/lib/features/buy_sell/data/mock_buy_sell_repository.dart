import '../../../../core/enums/sort_option.dart';
import '../../../../core/models/category_ref.dart';
import '../../../../core/models/contact.dart';
import '../../../../core/models/page.dart';
import '../../../../core/models/photo.dart';
import '../../../../core/models/user_ref.dart';
import '../domain/buy_sell_item.dart';
import 'buy_sell_repository.dart';

/// In-memory mock repository for Buy & Sell.
class MockBuySellRepository implements IBuySellRepository {
  static final List<CategoryRef> _categories = [
    const CategoryRef(id: 1, name: 'Books'),
    const CategoryRef(id: 2, name: 'Cycles'),
    const CategoryRef(id: 3, name: 'Electronics'),
    const CategoryRef(id: 4, name: 'Furniture'),
    const CategoryRef(id: 5, name: 'Lab Equipment'),
    const CategoryRef(id: 6, name: 'Others'),
  ];

  static final List<ListingItem> _mockData = [
    // 1
    ListingItem(
      id: '1',
      seller: const UserRef(id: 'user_aarav', name: 'Aarav Sharma'),
      sellerContact: const Contact(email: 'aaravs@iisc.ac.in', phone: '+919876543211'),
      title: 'IISc Chemistry Lab Coat (Size M)',
      description: '100% Cotton, clean condition with no chemical stains or tears. Ideal for first-year lab work. Washed and ironed. Fits 5\'7"-5\'10".',
      price: 350.0,
      category: const CategoryRef(id: 5, name: 'Lab Equipment'),
      location: 'Sarvam Hostel Block B',
      coverPhotoUrl: 'https://images.unsplash.com/photo-1584820927498-cfe5211fd8bf?w=700&auto=format&fit=crop&q=80',
      photos: const [
        Photo(s3Key: 'mock_coat_1', url: 'https://images.unsplash.com/photo-1584820927498-cfe5211fd8bf?w=700&auto=format&fit=crop&q=80', sortOrder: 0),
        Photo(s3Key: 'mock_coat_2', url: 'https://images.unsplash.com/photo-1576086213369-97a306d36557?w=700&auto=format&fit=crop&q=80', sortOrder: 1),
      ],
      status: ListingStatus.available,
      createdAt: DateTime.now().subtract(const Duration(hours: 3)),
    ),
    // 2
    ListingItem(
      id: '2',
      seller: const UserRef(id: 'user_priya', name: 'Priya Nair'),
      sellerContact: const Contact(email: 'priyan@iisc.ac.in', phone: '+919876543212'),
      title: 'Ergonomic Mesh Study Chair',
      description: 'Breathable mesh backrest with adjustable lumbar support and height pneumatic lever. Armrests intact. Minor scuff on base. Moving out of hostel.',
      price: 1800.0,
      category: const CategoryRef(id: 4, name: 'Furniture'),
      location: 'R-Block Hostel Room 204',
      coverPhotoUrl: 'https://images.unsplash.com/photo-1580481077194-c71c4c95f137?w=700&auto=format&fit=crop&q=80',
      photos: const [
        Photo(s3Key: 'mock_chair_1', url: 'https://images.unsplash.com/photo-1580481077194-c71c4c95f137?w=700&auto=format&fit=crop&q=80', sortOrder: 0),
        Photo(s3Key: 'mock_chair_2', url: 'https://images.unsplash.com/photo-1505797149-43b0069ec26b?w=700&auto=format&fit=crop&q=80', sortOrder: 1),
        Photo(s3Key: 'mock_chair_3', url: 'https://images.unsplash.com/photo-1592078615290-033ee584e267?w=700&auto=format&fit=crop&q=80', sortOrder: 2),
      ],
      status: ListingStatus.available,
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
    ),
    // 3
    ListingItem(
      id: '3',
      seller: const UserRef(id: 'user_rahul', name: 'Rahul Verma'),
      sellerContact: const Contact(email: 'rahulv@iisc.ac.in'),
      title: 'Engineering Mathematics by Erwin Kreyszig (10th Ed)',
      description: '10th Edition Hardcover. Contains neatly highlighted notes and previous year problem solutions in pencil (erasable). Spine tight.',
      price: 600.0,
      category: const CategoryRef(id: 1, name: 'Books'),
      location: 'Main Library Lawn',
      coverPhotoUrl: 'https://images.unsplash.com/photo-1544716278-ca5e3f4abd8c?w=700&auto=format&fit=crop&q=80',
      photos: const [
        Photo(s3Key: 'mock_book_1', url: 'https://images.unsplash.com/photo-1544716278-ca5e3f4abd8c?w=700&auto=format&fit=crop&q=80', sortOrder: 0),
        Photo(s3Key: 'mock_book_2', url: 'https://images.unsplash.com/photo-1497633762265-9d179a990aa6?w=700&auto=format&fit=crop&q=80', sortOrder: 1),
      ],
      status: ListingStatus.reserved,
      createdAt: DateTime.now().subtract(const Duration(days: 2)),
    ),
    // 4
    ListingItem(
      id: '4',
      seller: const UserRef(id: 'user_ananya', name: 'Ananya Roy'),
      sellerContact: const Contact(email: 'ananyar@iisc.ac.in'),
      title: 'Philips 1.5L Electric Kettle',
      description: 'Stainless steel body with auto cut-off protection. Fast boiling — perfect for hostel tea and instant noodles. Clean and works perfectly.',
      price: 750.0,
      category: const CategoryRef(id: 3, name: 'Electronics'),
      location: 'E-Block Hostel Room 112',
      coverPhotoUrl: 'https://images.unsplash.com/photo-1544816155-12df9643f363?w=700&auto=format&fit=crop&q=80',
      photos: const [
        Photo(s3Key: 'mock_kettle_1', url: 'https://images.unsplash.com/photo-1544816155-12df9643f363?w=700&auto=format&fit=crop&q=80', sortOrder: 0),
        Photo(s3Key: 'mock_kettle_2', url: 'https://images.unsplash.com/photo-1570784332176-fdd73da66f03?w=700&auto=format&fit=crop&q=80', sortOrder: 1),
      ],
      status: ListingStatus.sold,
      createdAt: DateTime.now().subtract(const Duration(days: 4)),
    ),
    // 5
    ListingItem(
      id: '5',
      seller: const UserRef(id: 'user_vikram', name: 'Vikram Singh'),
      sellerContact: const Contact(email: 'vikrams@iisc.ac.in'),
      title: 'Hero Sprint 21-Speed Mountain Bicycle',
      description: 'Dual disc brakes, front suspension fork, comes with dual LED lights and sturdy combination lock. Tyres at 85% tread. Serviced last month.',
      price: 4800.0,
      category: const CategoryRef(id: 2, name: 'Cycles'),
      location: 'Physics Department Cycle Stand',
      coverPhotoUrl: 'https://images.unsplash.com/photo-1485965120184-e220f721d03e?w=700&auto=format&fit=crop&q=80',
      photos: const [
        Photo(s3Key: 'mock_cycle_1', url: 'https://images.unsplash.com/photo-1485965120184-e220f721d03e?w=700&auto=format&fit=crop&q=80', sortOrder: 0),
        Photo(s3Key: 'mock_cycle_2', url: 'https://images.unsplash.com/photo-1532298229144-0ec0c57515c7?w=700&auto=format&fit=crop&q=80', sortOrder: 1),
        Photo(s3Key: 'mock_cycle_3', url: 'https://images.unsplash.com/photo-1576435728678-68d0fbf94e91?w=700&auto=format&fit=crop&q=80', sortOrder: 2),
      ],
      status: ListingStatus.available,
      createdAt: DateTime.now().subtract(const Duration(hours: 12)),
    ),
    // 6
    ListingItem(
      id: '6',
      seller: const UserRef(id: 'user_sneha', name: 'Sneha Iyer'),
      sellerContact: const Contact(email: 'snehai@iisc.ac.in'),
      title: 'Casio FX-991EX Classwiz Scientific Calculator',
      description: 'High-resolution display, 552 functions, QR code generator and spreadsheet mode. Original protective slide cover included. Mint condition.',
      price: 850.0,
      category: const CategoryRef(id: 3, name: 'Electronics'),
      location: 'CSA Department Foyer',
      coverPhotoUrl: 'https://images.unsplash.com/photo-1611125832047-1d7ad1e8e48f?w=700&auto=format&fit=crop&q=80',
      photos: const [
        Photo(s3Key: 'mock_calc_1', url: 'https://images.unsplash.com/photo-1611125832047-1d7ad1e8e48f?w=700&auto=format&fit=crop&q=80', sortOrder: 0),
        Photo(s3Key: 'mock_calc_2', url: 'https://images.unsplash.com/photo-1587145820266-a5951ee6f620?w=700&auto=format&fit=crop&q=80', sortOrder: 1),
      ],
      status: ListingStatus.available,
      createdAt: DateTime.now().subtract(const Duration(hours: 18)),
    ),
    // 7 (No Photo item for testing placeholder)
    ListingItem(
      id: '7',
      seller: const UserRef(id: 'user_karan', name: 'Karan Mehra'),
      sellerContact: const Contact(email: 'karanm@iisc.ac.in'),
      title: 'Solid Wood Bedside / Study Table',
      description: 'Lightweight table repurposed as bedside study unit. Height 45cm. Natural varnish finish, very sturdy. Easy to shift between hostel rooms. No pictures attached.',
      price: 800.0,
      category: const CategoryRef(id: 4, name: 'Furniture'),
      location: 'Aryabhata Hostel Block A',
      coverPhotoUrl: null,
      photos: const [],
      status: ListingStatus.available,
      createdAt: DateTime.now().subtract(const Duration(days: 3)),
    ),
    // 8
    ListingItem(
      id: '8',
      seller: const UserRef(id: 'user_tanvi', name: 'Tanvi Deshmukh'),
      sellerContact: const Contact(email: 'tanvid@iisc.ac.in', phone: '+919876543220'),
      title: 'Introduction to Algorithms (CLRS 4th Edition)',
      description: 'The standard textbook for algorithms. Paperback, barely used, no markings or stains. Ideal for CSA / CDS coursework and placements.',
      price: 1100.0,
      category: const CategoryRef(id: 1, name: 'Books'),
      location: 'Main Library Canteen',
      coverPhotoUrl: 'https://images.unsplash.com/photo-1532012164546-f432f2e3edd4?w=700&auto=format&fit=crop&q=80',
      photos: const [
        Photo(s3Key: 'mock_clrs_1', url: 'https://images.unsplash.com/photo-1532012164546-f432f2e3edd4?w=700&auto=format&fit=crop&q=80', sortOrder: 0),
        Photo(s3Key: 'mock_clrs_2', url: 'https://images.unsplash.com/photo-1512820790803-83ca734da794?w=700&auto=format&fit=crop&q=80', sortOrder: 1),
        Photo(s3Key: 'mock_clrs_3', url: 'https://images.unsplash.com/photo-1495446815901-a7297e633e8d?w=700&auto=format&fit=crop&q=80', sortOrder: 2),
      ],
      status: ListingStatus.available,
      createdAt: DateTime.now().subtract(const Duration(hours: 5)),
    ),
    // 9
    ListingItem(
      id: '9',
      seller: const UserRef(id: 'user_aditya', name: 'Aditya Gupta'),
      sellerContact: const Contact(email: 'adityag@iisc.ac.in', phone: '+919876543221'),
      title: 'Dell 24" Full HD IPS Monitor (75Hz, HDMI/VGA)',
      description: 'Zero dead pixels, anti-glare screen with ultrathin bezels. Perfect secondary monitor for research coding, papers, and dual-window setup.',
      price: 5400.0,
      category: const CategoryRef(id: 3, name: 'Electronics'),
      location: 'CDS Dept Research Lab 3',
      coverPhotoUrl: 'https://images.unsplash.com/photo-1527443224154-c4a3942d3acf?w=700&auto=format&fit=crop&q=80',
      photos: const [
        Photo(s3Key: 'mock_mon_1', url: 'https://images.unsplash.com/photo-1527443224154-c4a3942d3acf?w=700&auto=format&fit=crop&q=80', sortOrder: 0),
        Photo(s3Key: 'mock_mon_2', url: 'https://images.unsplash.com/photo-1547119957-637f8679db1e?w=700&auto=format&fit=crop&q=80', sortOrder: 1),
        Photo(s3Key: 'mock_mon_3', url: 'https://images.unsplash.com/photo-1585792180666-f7347c490ee2?w=700&auto=format&fit=crop&q=80', sortOrder: 2),
      ],
      status: ListingStatus.available,
      createdAt: DateTime.now().subtract(const Duration(hours: 8)),
    ),
    // 10
    ListingItem(
      id: '10',
      seller: const UserRef(id: 'user_rohit', name: 'Rohit Kulkarni'),
      sellerContact: const Contact(email: 'rohitk@iisc.ac.in'),
      title: 'Btwin Riverside 120 Hybrid Bicycle',
      description: 'Single-chainring 8-speed Microshift transmission. Lightweight steel frame. New brake pads installed 2 weeks ago at campus cycle workshop.',
      price: 4200.0,
      category: const CategoryRef(id: 2, name: 'Cycles'),
      location: 'Gymkhana Bicycle Shed',
      coverPhotoUrl: 'https://images.unsplash.com/photo-1507035895480-2b3156c31fc8?w=700&auto=format&fit=crop&q=80',
      photos: const [
        Photo(s3Key: 'mock_btwin_1', url: 'https://images.unsplash.com/photo-1507035895480-2b3156c31fc8?w=700&auto=format&fit=crop&q=80', sortOrder: 0),
        Photo(s3Key: 'mock_btwin_2', url: 'https://images.unsplash.com/photo-1532298229144-0ec0c57515c7?w=700&auto=format&fit=crop&q=80', sortOrder: 1),
      ],
      status: ListingStatus.available,
      createdAt: DateTime.now().subtract(const Duration(hours: 22)),
    ),
    // 11
    ListingItem(
      id: '11',
      seller: const UserRef(id: 'user_megha', name: 'Megha Rao'),
      sellerContact: const Contact(email: 'meghar@iisc.ac.in'),
      title: 'Logitech K380 Multi-Device Bluetooth Keyboard',
      description: 'Compact wireless keyboard, pairs with up to 3 devices (laptop, tablet, phone). Quiet low-profile keys. Fresh AAA batteries included.',
      price: 1400.0,
      category: const CategoryRef(id: 3, name: 'Electronics'),
      location: 'Nescafe Coffee Lawn',
      coverPhotoUrl: 'https://images.unsplash.com/photo-1587829741301-dc798b83add3?w=700&auto=format&fit=crop&q=80',
      photos: const [
        Photo(s3Key: 'mock_kb_1', url: 'https://images.unsplash.com/photo-1587829741301-dc798b83add3?w=700&auto=format&fit=crop&q=80', sortOrder: 0),
        Photo(s3Key: 'mock_kb_2', url: 'https://images.unsplash.com/photo-1618384887929-16ec33fab9ef?w=700&auto=format&fit=crop&q=80', sortOrder: 1),
        Photo(s3Key: 'mock_kb_3', url: 'https://images.unsplash.com/photo-1595225476474-87563907a212?w=700&auto=format&fit=crop&q=80', sortOrder: 2),
      ],
      status: ListingStatus.available,
      createdAt: DateTime.now().subtract(const Duration(days: 1, hours: 4)),
    ),
    // 12
    ListingItem(
      id: '12',
      seller: const UserRef(id: 'user_siddharth', name: 'Siddharth Jain'),
      sellerContact: const Contact(email: 'siddharthj@iisc.ac.in'),
      title: 'Digital Oscilloscope Probe & Test Leads Kit',
      description: '100MHz 10X/1X switchable oscilloscope probes with BNC connectors, ground clips, and IC test hooks. Tested on Tektronix scopes in ECE labs.',
      price: 650.0,
      category: const CategoryRef(id: 5, name: 'Lab Equipment'),
      location: 'ECE Department Ground Floor',
      coverPhotoUrl: 'https://images.unsplash.com/photo-1581092160607-ee22621dd758?w=700&auto=format&fit=crop&q=80',
      photos: const [
        Photo(s3Key: 'mock_probe_1', url: 'https://images.unsplash.com/photo-1581092160607-ee22621dd758?w=700&auto=format&fit=crop&q=80', sortOrder: 0),
        Photo(s3Key: 'mock_probe_2', url: 'https://images.unsplash.com/photo-1581092335397-9583fe92d232?w=700&auto=format&fit=crop&q=80', sortOrder: 1),
      ],
      status: ListingStatus.available,
      createdAt: DateTime.now().subtract(const Duration(days: 1, hours: 8)),
    ),
    // 13
    ListingItem(
      id: '13',
      seller: const UserRef(id: 'user_divya', name: 'Divya Sen'),
      sellerContact: const Contact(email: 'divyas@iisc.ac.in'),
      title: 'Yonex Nanoray 10F Badminton Racket with Cover',
      description: 'Full graphite shaft with isometric head frame. Strung at 22 lbs with BG65 string. Used for one semester at Gymkhana badminton courts.',
      price: 1200.0,
      category: const CategoryRef(id: 6, name: 'Others'),
      location: 'Gymkhana Sports Complex',
      coverPhotoUrl: 'https://images.unsplash.com/photo-1626224583764-f87db24ac4ea?w=700&auto=format&fit=crop&q=80',
      photos: const [
        Photo(s3Key: 'mock_racket_1', url: 'https://images.unsplash.com/photo-1626224583764-f87db24ac4ea?w=700&auto=format&fit=crop&q=80', sortOrder: 0),
        Photo(s3Key: 'mock_racket_2', url: 'https://images.unsplash.com/photo-1613918108466-292b78a8ef95?w=700&auto=format&fit=crop&q=80', sortOrder: 1),
      ],
      status: ListingStatus.available,
      createdAt: DateTime.now().subtract(const Duration(days: 2, hours: 3)),
    ),
    // 14
    ListingItem(
      id: '14',
      seller: const UserRef(id: 'user_harsh', name: 'Harsh Vardhan'),
      sellerContact: const Contact(email: 'harshv@iisc.ac.in'),
      title: 'Bajaj 24L Personal Room Air Cooler',
      description: 'Honeycomb cooling pads with 3-speed blower and castor wheels. Works great during Bangalore summer in hostel rooms. Clean water tank.',
      price: 2500.0,
      category: const CategoryRef(id: 4, name: 'Furniture'),
      location: 'Sarvam Hostel Block D',
      coverPhotoUrl: 'https://images.unsplash.com/photo-1585338107529-13afc5f02586?w=700&auto=format&fit=crop&q=80',
      photos: const [
        Photo(s3Key: 'mock_cooler_1', url: 'https://images.unsplash.com/photo-1585338107529-13afc5f02586?w=700&auto=format&fit=crop&q=80', sortOrder: 0),
      ],
      status: ListingStatus.available,
      createdAt: DateTime.now().subtract(const Duration(days: 2, hours: 10)),
    ),
    // 15
    ListingItem(
      id: '15',
      seller: const UserRef(id: 'user_deepak', name: 'Deepak Mishra'),
      sellerContact: const Contact(email: 'deepakm@iisc.ac.in'),
      title: 'Computer Systems: A Programmer\'s Perspective (CS:APP 3rd Ed)',
      description: 'Hardcover textbook by Bryant & O\'Hallaron. Excellent coverage of computer architecture, linking, virtual memory and concurrency.',
      price: 850.0,
      category: const CategoryRef(id: 1, name: 'Books'),
      location: 'CSA Department Coffee Corner',
      coverPhotoUrl: 'https://images.unsplash.com/photo-1497633762265-9d179a990aa6?w=700&auto=format&fit=crop&q=80',
      photos: const [
        Photo(s3Key: 'mock_csapp_1', url: 'https://images.unsplash.com/photo-1497633762265-9d179a990aa6?w=700&auto=format&fit=crop&q=80', sortOrder: 0),
      ],
      status: ListingStatus.available,
      createdAt: DateTime.now().subtract(const Duration(days: 3, hours: 1)),
    ),
    // 16
    ListingItem(
      id: '16',
      seller: const UserRef(id: 'user_anmol', name: 'Anmol Sethi'),
      sellerContact: const Contact(email: 'anmols@iisc.ac.in'),
      title: 'Anker PowerCore 20,000mAh Portable Charger (20W USB-C)',
      description: 'High capacity battery pack with PowerIQ 3.0 fast charging. Charges iPhone 14 about 4.5 times. Sleek matte black finish, scratch-free.',
      price: 1350.0,
      category: const CategoryRef(id: 3, name: 'Electronics'),
      location: 'Faculty Club Gate',
      coverPhotoUrl: 'https://images.unsplash.com/photo-1609592424368-24cf23055375?w=700&auto=format&fit=crop&q=80',
      photos: const [
        Photo(s3Key: 'mock_pb_1', url: 'https://images.unsplash.com/photo-1609592424368-24cf23055375?w=700&auto=format&fit=crop&q=80', sortOrder: 0),
        Photo(s3Key: 'mock_pb_2', url: 'https://images.unsplash.com/photo-1583863788434-e58a36330cf0?w=700&auto=format&fit=crop&q=80', sortOrder: 1),
      ],
      status: ListingStatus.available,
      createdAt: DateTime.now().subtract(const Duration(days: 3, hours: 6)),
    ),
    // 17
    ListingItem(
      id: '17',
      seller: const UserRef(id: 'user_neha', name: 'Neha Joshi'),
      sellerContact: const Contact(email: 'nehaj@iisc.ac.in'),
      title: 'Hercules Street Cat Pro Cycle with Front Basket',
      description: 'Single-gear campus cycle, low maintenance, sturdy rear carrier and front wire basket. Very comfortable padded saddle.',
      price: 1950.0,
      category: const CategoryRef(id: 2, name: 'Cycles'),
      location: 'K-Block Girls Hostel',
      coverPhotoUrl: 'https://images.unsplash.com/photo-1485965120184-e220f721d03e?w=700&auto=format&fit=crop&q=80',
      photos: const [
        Photo(s3Key: 'mock_cat_1', url: 'https://images.unsplash.com/photo-1485965120184-e220f721d03e?w=700&auto=format&fit=crop&q=80', sortOrder: 0),
        Photo(s3Key: 'mock_cat_2', url: 'https://images.unsplash.com/photo-1507035895480-2b3156c31fc8?w=700&auto=format&fit=crop&q=80', sortOrder: 1),
      ],
      status: ListingStatus.available,
      createdAt: DateTime.now().subtract(const Duration(days: 4, hours: 2)),
    ),
    // 18
    ListingItem(
      id: '18',
      seller: const UserRef(id: 'user_saurabh', name: 'Saurabh Pant'),
      sellerContact: const Contact(email: 'saurabhp@iisc.ac.in'),
      title: 'Foldable Metal Study Table & Laptop Stand',
      description: 'Compact foldable desk (80cm x 50cm) with powder-coated steel legs. Folds completely flat to slide under bed when not in use.',
      price: 950.0,
      category: const CategoryRef(id: 4, name: 'Furniture'),
      location: 'R-Block Hostel',
      coverPhotoUrl: 'https://images.unsplash.com/photo-1518455027359-f3f8164ba6bd?w=700&auto=format&fit=crop&q=80',
      photos: const [
        Photo(s3Key: 'mock_foldtable_1', url: 'https://images.unsplash.com/photo-1518455027359-f3f8164ba6bd?w=700&auto=format&fit=crop&q=80', sortOrder: 0),
        Photo(s3Key: 'mock_foldtable_2', url: 'https://images.unsplash.com/photo-1533090161767-e6ffed986c88?w=700&auto=format&fit=crop&q=80', sortOrder: 1),
      ],
      status: ListingStatus.available,
      createdAt: DateTime.now().subtract(const Duration(days: 4, hours: 9)),
    ),
    // 19
    ListingItem(
      id: '19',
      seller: const UserRef(id: 'user_rishi', name: 'Rishi Kapoor'),
      sellerContact: const Contact(email: 'rishik@iisc.ac.in'),
      title: 'Raspberry Pi 4 Model B (4GB RAM) + Case & 32GB Card',
      description: 'Includes official transparent acrylic case with silent cooling fan, Micro-HDMI to HDMI cable, and pre-flashed Raspberry Pi OS card.',
      price: 3800.0,
      category: const CategoryRef(id: 3, name: 'Electronics'),
      location: 'DESE Department Room 210',
      coverPhotoUrl: 'https://images.unsplash.com/photo-1555774698-0b77e0d5fac6?w=700&auto=format&fit=crop&q=80',
      photos: const [
        Photo(s3Key: 'mock_pi_1', url: 'https://images.unsplash.com/photo-1555774698-0b77e0d5fac6?w=700&auto=format&fit=crop&q=80', sortOrder: 0),
        Photo(s3Key: 'mock_pi_2', url: 'https://images.unsplash.com/photo-1518770660439-4636190af475?w=700&auto=format&fit=crop&q=80', sortOrder: 1),
      ],
      status: ListingStatus.available,
      createdAt: DateTime.now().subtract(const Duration(days: 5, hours: 4)),
    ),
    // 20
    ListingItem(
      id: '20',
      seller: const UserRef(id: 'user_kavita', name: 'Kavita Das'),
      sellerContact: const Contact(email: 'kavitad@iisc.ac.in'),
      title: 'Pattern Recognition and Machine Learning (Bishop)',
      description: 'Hardcover international edition. Comprehensive foundation in Bayesian machine learning and graphical models. Clean pages.',
      price: 1250.0,
      category: const CategoryRef(id: 1, name: 'Books'),
      location: 'Main Library 2nd Floor',
      coverPhotoUrl: 'https://images.unsplash.com/photo-1544716278-ca5e3f4abd8c?w=700&auto=format&fit=crop&q=80',
      photos: const [
        Photo(s3Key: 'mock_bishop_1', url: 'https://images.unsplash.com/photo-1544716278-ca5e3f4abd8c?w=700&auto=format&fit=crop&q=80', sortOrder: 0),
      ],
      status: ListingStatus.available,
      createdAt: DateTime.now().subtract(const Duration(days: 5, hours: 12)),
    ),
    // 21
    ListingItem(
      id: '21',
      seller: const UserRef(id: 'user_tarun', name: 'Tarun Reddy'),
      sellerContact: const Contact(email: 'tarunr@iisc.ac.in'),
      title: 'Soldering Iron Kit (60W Temp Controlled) with Stand & Solder',
      description: 'Temperature adjustable from 200°C to 450°C. Comes with 5 interchangeable tips, desoldering pump, tweezers, and solder wire spool.',
      price: 550.0,
      category: const CategoryRef(id: 5, name: 'Lab Equipment'),
      location: 'Robotics Lab Mechanical Engg',
      coverPhotoUrl: 'https://images.unsplash.com/photo-1581092160607-ee22621dd758?w=700&auto=format&fit=crop&q=80',
      photos: const [
        Photo(s3Key: 'mock_solder_1', url: 'https://images.unsplash.com/photo-1581092160607-ee22621dd758?w=700&auto=format&fit=crop&q=80', sortOrder: 0),
      ],
      status: ListingStatus.available,
      createdAt: DateTime.now().subtract(const Duration(days: 6)),
    ),
    // 22
    ListingItem(
      id: '22',
      seller: const UserRef(id: 'user_ishita', name: 'Ishita Banerjee'),
      sellerContact: const Contact(email: 'ishitab@iisc.ac.in'),
      title: 'Wildcraft 35L Water-Resistant Laptop Backpack',
      description: 'Padded laptop compartment (fits up to 15.6"), rain cover included in bottom zipper, ergonomic shoulder straps with chest clip.',
      price: 850.0,
      category: const CategoryRef(id: 6, name: 'Others'),
      location: 'Sarvam Hostel Mess',
      coverPhotoUrl: 'https://images.unsplash.com/photo-1553062407-98eeb64c6a62?w=700&auto=format&fit=crop&q=80',
      photos: const [
        Photo(s3Key: 'mock_bag_1', url: 'https://images.unsplash.com/photo-1553062407-98eeb64c6a62?w=700&auto=format&fit=crop&q=80', sortOrder: 0),
      ],
      status: ListingStatus.available,
      createdAt: DateTime.now().subtract(const Duration(days: 6, hours: 8)),
    ),
    // 23
    ListingItem(
      id: '23',
      seller: const UserRef(id: 'user_pranav', name: 'Pranav Saxena'),
      sellerContact: const Contact(email: 'pranavs@iisc.ac.in'),
      title: 'Seagate One Touch 2TB External USB 3.0 Hard Drive',
      description: 'Tested with CrystalDiskInfo (100% health, zero bad sectors). Password protection and AES-256 hardware encryption supported.',
      price: 3200.0,
      category: const CategoryRef(id: 3, name: 'Electronics'),
      location: 'CSA Dept Student Lounge',
      coverPhotoUrl: 'https://images.unsplash.com/photo-1597872200969-2b65d56bd16b?w=700&auto=format&fit=crop&q=80',
      photos: const [
        Photo(s3Key: 'mock_hdd_1', url: 'https://images.unsplash.com/photo-1597872200969-2b65d56bd16b?w=700&auto=format&fit=crop&q=80', sortOrder: 0),
      ],
      status: ListingStatus.available,
      createdAt: DateTime.now().subtract(const Duration(days: 7)),
    ),
    // 24
    ListingItem(
      id: '24',
      seller: const UserRef(id: 'user_alka', name: 'Alka Swaminathan'),
      sellerContact: const Contact(email: 'alkas@iisc.ac.in'),
      title: 'Sleepwell 4-Inch Coir & Foam Single Bed Mattress',
      description: 'Standard hostel bed dimensions (72" x 36"). Dual firmness sides (firm coir on one side, soft foam on reverse). Very clean.',
      price: 1300.0,
      category: const CategoryRef(id: 4, name: 'Furniture'),
      location: 'New Girls Hostel Block C',
      coverPhotoUrl: 'https://images.unsplash.com/photo-1631049307264-da0ec9d70304?w=700&auto=format&fit=crop&q=80',
      photos: const [
        Photo(s3Key: 'mock_mattress_1', url: 'https://images.unsplash.com/photo-1631049307264-da0ec9d70304?w=700&auto=format&fit=crop&q=80', sortOrder: 0),
      ],
      status: ListingStatus.available,
      createdAt: DateTime.now().subtract(const Duration(days: 7, hours: 14)),
    )
  ];

  @override
  Future<PaginatedResponse<ListingItem>> fetchListingsPage({
    String query = '',
    int? categoryId,
    double? minPrice,
    double? maxPrice,
    List<ListingStatus>? statusList,
    String? sellerId,
    SortOption sortOption = SortOption.newest,
    int limit = 20,
    int offset = 0,
  }) async {
    await Future.delayed(const Duration(milliseconds: 320));
    final filtered = _mockData.where((item) {
      final matchesQuery = query.isEmpty ||
          item.title.toLowerCase().contains(query.toLowerCase()) ||
          item.description.toLowerCase().contains(query.toLowerCase()) ||
          item.location.toLowerCase().contains(query.toLowerCase());
      final matchesCategory = categoryId == null || item.category.id == categoryId;
      final matchesStatus = statusList == null ? true : statusList.contains(item.status);
      final matchesMinPrice = minPrice == null || item.price >= minPrice;
      final matchesMaxPrice = maxPrice == null || item.price <= maxPrice;
      final matchesSeller = sellerId == null || sellerId.isEmpty || item.seller.id == sellerId;

      return matchesQuery &&
          matchesCategory &&
          matchesStatus &&
          matchesMinPrice &&
          matchesMaxPrice &&
          matchesSeller;
    }).toList();

    filtered.sort((a, b) => switch (sortOption) {
          SortOption.priceLowToHigh => a.price.compareTo(b.price),
          SortOption.priceHighToLow => b.price.compareTo(a.price),
          _ => b.createdAt.compareTo(a.createdAt),
        });

    if (offset >= filtered.length) {
      return PaginatedResponse(items: [], limit: limit, offset: offset, hasMore: false);
    }

    final endIndex = (offset + limit).clamp(0, filtered.length);
    final slice = filtered.sublist(offset, endIndex);
    final hasMore = filtered.length > offset + limit;

    return PaginatedResponse(
      items: slice,
      limit: limit,
      offset: offset,
      hasMore: hasMore,
    );
  }

  @override
  Future<List<ListingItem>> fetchListings({
    String query = '',
    String category = 'All',
    int? categoryId,
    SortOption sortOption = SortOption.newest,
    ListingStatus? statusFilter,
    double? minPrice,
    double? maxPrice,
    DateTime? fromDate,
    DateTime? toDate,
    String? sellerId,
    int page = 1,
    int limit = 50,
    int offset = 0,
  }) async {
    await Future.delayed(const Duration(milliseconds: 320));
    var items = _mockData.where((item) {
      final matchesQuery = query.isEmpty ||
          item.title.toLowerCase().contains(query.toLowerCase()) ||
          item.description.toLowerCase().contains(query.toLowerCase()) ||
          item.location.toLowerCase().contains(query.toLowerCase());
      final matchesCategory = category == 'All' ||
          item.category.name == category ||
          (categoryId != null && item.category.id == categoryId);
      final matchesStatus = statusFilter == null || item.status == statusFilter;
      final matchesMinPrice = minPrice == null || item.price >= minPrice;
      final matchesMaxPrice = maxPrice == null || item.price <= maxPrice;
      final matchesFromDate = fromDate == null || item.createdAt.isAfter(fromDate);
      final matchesToDate = toDate == null || item.createdAt.isBefore(toDate);
      final matchesSeller = sellerId == null || sellerId.isEmpty || item.seller.id == sellerId;

      return matchesQuery &&
          matchesCategory &&
          matchesStatus &&
          matchesMinPrice &&
          matchesMaxPrice &&
          matchesFromDate &&
          matchesToDate &&
          matchesSeller;
    }).toList();

    switch (sortOption) {
      case SortOption.oldest:
        items.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        break;
      case SortOption.priceLowToHigh:
        items.sort((a, b) => a.price.compareTo(b.price));
        break;
      case SortOption.priceHighToLow:
        items.sort((a, b) => b.price.compareTo(a.price));
        break;
      case SortOption.discountHighToLow:
        items.sort((a, b) => b.price.compareTo(a.price));
        break;
      case SortOption.newest:
        items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
    }

    final effectiveOffset = offset > 0 ? offset : (page > 1 ? (page - 1) * limit : 0);
    if (effectiveOffset >= items.length) return [];
    final endIndex = (effectiveOffset + limit).clamp(0, items.length);
    return items.sublist(effectiveOffset, endIndex);
  }

  @override
  Future<ListingItem?> getListingById(String id) async {
    try {
      return _mockData.firstWhere((item) => item.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<ListingItem> addListing(
    ListingItem item, {
    List<String> photoKeys = const [],
  }) async {
    _mockData.insert(0, item);
    return item;
  }

  @override
  Future<ListingItem> updateListing(
    String id, {
    String? title,
    String? description,
    double? price,
    int? categoryId,
    String? location,
  }) async {
    final index = _mockData.indexWhere((it) => it.id == id);
    if (index == -1) throw Exception('Listing not found');

    CategoryRef newCat = _mockData[index].category;
    if (categoryId != null) {
      newCat = _categories.firstWhere(
        (c) => c.id == categoryId,
        orElse: () => CategoryRef(id: categoryId, name: 'Other'),
      );
    }

    final updated = _mockData[index].copyWith(
      title: title,
      description: description,
      price: price,
      category: newCat,
      location: location,
      updatedAt: DateTime.now(),
    );
    _mockData[index] = updated;
    return updated;
  }

  @override
  Future<void> updateStatus(String id, ListingStatus newStatus) async {
    final index = _mockData.indexWhere((item) => item.id == id);
    if (index != -1) {
      _mockData[index] = _mockData[index].copyWith(status: newStatus);
    }
  }

  @override
  Future<void> replacePhotos(String id, List<String> photoKeys) async {
    final index = _mockData.indexWhere((item) => item.id == id);
    if (index != -1) {
      final newPhotos = photoKeys.asMap().entries.map((e) {
        return Photo(
          s3Key: e.value,
          url: 'https://picsum.photos/seed/${e.value}/600/400',
          sortOrder: e.key,
        );
      }).toList();

      _mockData[index] = _mockData[index].copyWith(
        photos: newPhotos,
        coverPhotoUrl: newPhotos.isNotEmpty ? newPhotos.first.url : null,
      );
    }
  }

  @override
  Future<void> deleteListing(String id, {String? reason}) async {
    _mockData.removeWhere((item) => item.id == id);
  }

  @override
  Future<List<CategoryRef>> fetchCategories() async {
    return List.unmodifiable(_categories);
  }

  @override
  Future<CategoryRef> createCategory(String name) async {
    final clean = name.trim();
    final existing = _categories.where(
      (c) => c.name.toLowerCase() == clean.toLowerCase(),
    );
    if (existing.isNotEmpty) return existing.first;

    final newCat = CategoryRef(id: _categories.length + 1, name: clean);
    _categories.add(newCat);
    return newCat;
  }

  @override
  Future<CategoryRef> updateCategory(int id, String newName) async {
    final clean = newName.trim();
    final idx = _categories.indexWhere((c) => c.id == id);
    if (idx != -1) {
      _categories[idx] = CategoryRef(id: id, name: clean);
      return _categories[idx];
    }
    throw Exception('Category not found');
  }

  @override
  Future<void> deleteCategory(int id) async {
    _categories.removeWhere((c) => c.id == id);
  }
}
