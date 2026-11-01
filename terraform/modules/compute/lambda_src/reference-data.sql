-- ============================================================================
-- CampusHub Comprehensive Reference & Seed Data
-- IISc Student Community Platform (DS252 Intro to Cloud Computing)
-- ============================================================================

-- 1. Campus Services (Landing Page)
INSERT INTO campus_services (name, description, category, url, phone, sort_order)
SELECT v.name, v.description, v.category::campus_service_category, v.url, v.phone, v.sort_order
FROM (VALUES
    ('Health Centre', 'Doctors, pharmacy, lab tests and specialist clinics on campus.',
     'health', 'https://healthcentre.iisc.ac.in/', NULL, 10),
    ('Emergency / Ambulance', 'Health Centre emergency line, any time.',
     'health', NULL, '080-2293-4444', 20),
    ('Wellness Centre', 'Free, confidential counselling and wellbeing support for students.',
     'wellbeing', 'https://wellness.iisc.ac.in/', NULL, 10),
    ('Student grievance redressal', 'How to raise an academic or administrative grievance, and who handles it.',
     'grievance', 'https://www.iisc.ac.in/wp-content/uploads/2025/01/Approval-Note_Students-Grievances-Guidelines.pdf', NULL, 10),
    ('Internal Committee Against Sexual Harassment (ICASH)', 'Report sexual harassment, confidentially.',
     'grievance', 'https://www.iisc.ac.in/icash/', NULL, 20),
    ('Complaints about caste-based discrimination', 'Where to report caste-based discrimination.',
     'grievance', 'https://www.iisc.ac.in/complaints-related-to-caste-based-discrimination/', NULL, 30),
    ('Anti-ragging', 'Anti-ragging committee and squad contacts.',
     'grievance', 'https://www.iisc.ac.in/wp-content/uploads/2024/08/Colleges-University-Institution_Website_Information.pdf', NULL, 40)
) AS v(name, description, category, url, phone, sort_order)
WHERE NOT EXISTS (SELECT 1 FROM campus_services c WHERE c.name = v.name);

-- 2. Academic Departments
INSERT INTO departments (name) VALUES
    ('Computational and Data Sciences (CDS)'),
    ('Computer Science and Automation (CSA)'),
    ('Electrical Communication Engineering (ECE)'),
    ('Electrical Engineering (EE)')
ON CONFLICT (name) DO NOTHING;

-- 3. Academic Courses
DO $$
DECLARE
    cds_id uuid;
    csa_id uuid;
    ece_id uuid;
    ee_id  uuid;
BEGIN
    SELECT id INTO cds_id FROM departments WHERE name LIKE 'Computational and Data Sciences%' LIMIT 1;
    SELECT id INTO csa_id FROM departments WHERE name LIKE 'Computer Science and Automation%' LIMIT 1;
    SELECT id INTO ece_id FROM departments WHERE name LIKE 'Electrical Communication Engineering%' LIMIT 1;
    SELECT id INTO ee_id  FROM departments WHERE name LIKE 'Electrical Engineering%' LIMIT 1;

    -- CDS Courses
    IF cds_id IS NOT NULL THEN
        INSERT INTO courses (department_id, code, name) VALUES
            (cds_id, 'DS 252', 'Cloud Computing'),
            (cds_id, 'DS 221', 'Introduction to Scalable Systems'),
            (cds_id, 'DS 211', 'Numerical Optimization'),
            (cds_id, 'DS 265', 'Deep Learning for Computer Vision'),
            (cds_id, 'DS 256', 'Scalable Systems for Data Science'),
            (cds_id, 'DS 284', 'Numerical Linear Algebra'),
            (cds_id, 'DS 207', 'Introduction to Natural Language Processing'),
            (cds_id, 'DS 215', 'Introduction to Data Science')
        ON CONFLICT (department_id, code) DO NOTHING;
    END IF;

    -- CSA Courses
    IF csa_id IS NOT NULL THEN
        INSERT INTO courses (department_id, code, name) VALUES
            (csa_id, 'E0 225', 'Design and Analysis of Algorithms'),
            (csa_id, 'E0 243', 'Computer Architecture'),
            (csa_id, 'E0 253', 'Operating Systems'),
            (csa_id, 'E0 270', 'Machine Learning'),
            (csa_id, 'E0 256', 'Computer Systems Security')
        ON CONFLICT (department_id, code) DO NOTHING;
    END IF;

    -- ECE Courses
    IF ece_id IS NOT NULL THEN
        INSERT INTO courses (department_id, code, name) VALUES
            (ece_id, 'E2 201', 'Information Theory and Coding'),
            (ece_id, 'E2 202', 'Random Processes'),
            (ece_id, 'E2 211', 'Digital Communication')
        ON CONFLICT (department_id, code) DO NOTHING;
    END IF;

    -- EE Courses
    IF ee_id IS NOT NULL THEN
        INSERT INTO courses (department_id, code, name) VALUES
            (ee_id, 'E1 213', 'Pattern Recognition and Neural Networks'),
            (ee_id, 'E1 222', 'Stochastic Processes and Queuing Theory'),
            (ee_id, 'E1 241', 'Dynamics of Linear Systems')
        ON CONFLICT (department_id, code) DO NOTHING;
    END IF;
END $$;

-- 4. Seed Users (Admin & Students)
DO $$
DECLARE
    cds_id uuid;
BEGIN
    SELECT id INTO cds_id FROM departments WHERE name LIKE 'Computational and Data Sciences%' LIMIT 1;

    INSERT INTO users (cognito_sub, email, name, base_role, department_id, programme, graduation_year) VALUES
        ('dev|dinkylakhani@iisc.ac.in', 'dinkylakhani@iisc.ac.in', 'Dinky Lakhani', 'admin', cds_id, 'M.Tech CDS', 2026),
        ('dev|ananyarao@iisc.ac.in', 'ananyarao@iisc.ac.in', 'Ananya Rao', 'signed_in', cds_id, 'M.Tech CDS', 2026),
        ('dev|rohansharma@iisc.ac.in', 'rohansharma@iisc.ac.in', 'Rohan Sharma', 'signed_in', cds_id, 'PhD CDS', 2027),
        ('dev|priyaiyer@iisc.ac.in', 'priyaiyer@iisc.ac.in', 'Priya Iyer', 'signed_in', cds_id, 'M.Tech Research', 2026),
        ('dev|arjunnair@iisc.ac.in', 'arjunnair@iisc.ac.in', 'Arjun Nair', 'signed_in', cds_id, 'M.Tech CDS', 2026)
    ON CONFLICT (email) DO UPDATE SET base_role = EXCLUDED.base_role;
END $$;

-- 5. Buy & Sell Categories
INSERT INTO bs_categories (name) VALUES
    ('Cycles & Mobility'),
    ('Electronics & Gadgets'),
    ('Books & Notes'),
    ('Room & Hostel Essentials'),
    ('Sports & Fitness'),
    ('Clothing & Accessories'),
    ('Other')
ON CONFLICT (name_key) DO NOTHING;

-- 6. Buy & Sell Sample Listings
DO $$
DECLARE
    admin_id uuid;
    cat_cycles int;
    cat_elec   int;
    cat_books  int;
    cat_hostel int;
    cat_sports int;
BEGIN
    SELECT id INTO admin_id FROM users WHERE email = 'dinkylakhani@iisc.ac.in' LIMIT 1;
    IF admin_id IS NULL THEN
        SELECT id INTO admin_id FROM users LIMIT 1;
    END IF;

    SELECT id INTO cat_cycles FROM bs_categories WHERE name LIKE 'Cycles%' LIMIT 1;
    SELECT id INTO cat_elec   FROM bs_categories WHERE name LIKE 'Electronics%' LIMIT 1;
    SELECT id INTO cat_books  FROM bs_categories WHERE name LIKE 'Books%' LIMIT 1;
    SELECT id INTO cat_hostel FROM bs_categories WHERE name LIKE 'Room%' LIMIT 1;
    SELECT id INTO cat_sports FROM bs_categories WHERE name LIKE 'Sports%' LIMIT 1;

    IF admin_id IS NOT NULL AND cat_cycles IS NOT NULL THEN
        INSERT INTO listings (seller_id, title, description, price, category_id, location, status) VALUES
            (admin_id, 'Hero Sprint Next 26T Mountain Bike', 'In great riding condition. Front suspension, 21 gears, newly replaced brake pads. Suitable for campus commutes.', 3500.00, cat_cycles, 'Kavery Hostel', 'available'),
            (admin_id, 'Pattern Recognition & Machine Learning (Bishop)', 'Classic PRML hardcover textbook. Pristine condition with no markings or highlights. Highly recommended for DS 265 / E0 270.', 650.00, cat_books, 'CDS Department', 'available'),
            (admin_id, 'LG 24-inch IPS Full HD Monitor (24MP88HV)', 'Crisp color display, dual HDMI ports, borderless design. Includes HDMI cable and power adapter. Ideal for lab dual-screen setup.', 5500.00, cat_elec, 'Raman Building', 'available'),
            (admin_id, 'Ergonomic Mesh Study Chair with Lumbar Support', 'Adjustable height and tilt lock. Breathable mesh back. Great for long thesis writing and coding sessions.', 2200.00, cat_hostel, 'Ashoka Hostel', 'available'),
            (admin_id, 'Yonex Carbonex 8000 Badminton Racquet', 'Lightweight carbon graphite frame with full cover. Strung at 24 lbs with BG65 strings.', 1100.00, cat_sports, 'Gymkhana Courts', 'available'),
            (admin_id, 'Casio FX-991CW ClassWiz Scientific Calculator', 'Natural textbook display, matrix/vector calculations, permitted in all IISc exams. With protective slide-on hard case.', 750.00, cat_elec, 'Main Building', 'available'),
            (admin_id, 'Introduction to Algorithms (CLRS 3rd Edition)', 'Indispensable guide for DS 221 and algorithms prep. Clean pages, no torn leaves.', 850.00, cat_books, 'JRD Tata Library', 'available'),
            (admin_id, 'Decathlon Quechua 20L Water-Resistant Backpack', 'Two zipped compartments with laptop pocket. Comfortable padded shoulder straps. Very good condition.', 600.00, cat_hostel, 'Kavery Hostel', 'available')
        ON CONFLICT DO NOTHING;
    END IF;
END $$;

-- 7. Lost & Found Categories
INSERT INTO lf_categories (name) VALUES
    ('ID Cards & Wallets'),
    ('Keys'),
    ('Electronics & Chargers'),
    ('Bottles & Flasks'),
    ('Bags & Umbrellas'),
    ('Documents & Notebooks'),
    ('Other')
ON CONFLICT (name_key) DO NOTHING;

-- 8. Lost & Found Sample Reports
DO $$
DECLARE
    admin_id uuid;
    cat_idcard int;
    cat_keys   int;
    cat_elec   int;
    cat_bottle int;
    cat_bags   int;
BEGIN
    SELECT id INTO admin_id FROM users WHERE email = 'dinkylakhani@iisc.ac.in' LIMIT 1;
    IF admin_id IS NULL THEN
        SELECT id INTO admin_id FROM users LIMIT 1;
    END IF;

    SELECT id INTO cat_idcard FROM lf_categories WHERE name LIKE 'ID%' LIMIT 1;
    SELECT id INTO cat_keys   FROM lf_categories WHERE name LIKE 'Keys%' LIMIT 1;
    SELECT id INTO cat_elec   FROM lf_categories WHERE name LIKE 'Electronics%' LIMIT 1;
    SELECT id INTO cat_bottle FROM lf_categories WHERE name LIKE 'Bottles%' LIMIT 1;
    SELECT id INTO cat_bags   FROM lf_categories WHERE name LIKE 'Bags%' LIMIT 1;

    IF admin_id IS NOT NULL AND cat_idcard IS NOT NULL THEN
        -- Lost Reports
        INSERT INTO lost_reports (reporter_id, description, category_id, lost_at, location, status) VALUES
            (admin_id, 'IISc Student ID Card in blue lanyard. Lost around evening near the canteen.', cat_idcard, now() - interval '2 days', 'Near Sarvam Complex', 'open'),
            (admin_id, 'Blue Milton Thermosteel Flask 750ml with silver cap. Left on study desk.', cat_bottle, now() - interval '1 day', 'JRD Tata Memorial Library 1st Floor', 'open'),
            (admin_id, 'Sony WF-C500 Black Wireless Earbuds Charging Case (without buds).', cat_elec, now() - interval '3 days', 'Gymkhana Sports Ground', 'open'),
            (admin_id, 'Hostel Room Key with Marvel Superman metal keychain.', cat_keys, now() - interval '4 hours', 'Kavery Hostel Mess', 'open')
        ON CONFLICT DO NOTHING;

        -- Found Reports
        INSERT INTO found_reports (reporter_id, description, category_id, found_at, location, status) VALUES
            (admin_id, 'Casio FX-991EX Scientific Calculator found left on table after seminar.', cat_elec, now() - interval '1 day', 'CDS Department Seminar Hall', 'open'),
            (admin_id, 'Black Decathlon Windproof Umbrella found near the entrance rack.', cat_bags, now() - interval '2 days', 'Main Dining Hall (Prakruthi)', 'open'),
            (admin_id, 'IISc Department Identity Card found on table outside cafe. Please collect after ID verification.', cat_idcard, now() - interval '12 hours', 'Nesara Cafe', 'open')
        ON CONFLICT DO NOTHING;
    END IF;
END $$;

-- 9. Course Feedback & Survival Guide Seed for DS 252 (Cloud Computing)
DO $$
DECLARE
    ds252_id uuid;
    u1 uuid;
    u2 uuid;
    u3 uuid;
BEGIN
    SELECT id INTO ds252_id FROM courses WHERE code = 'DS 252' LIMIT 1;
    SELECT id INTO u1 FROM users WHERE email = 'ananya.rao@iisc.ac.in' LIMIT 1;
    SELECT id INTO u2 FROM users WHERE email = 'rohan.sharma@iisc.ac.in' LIMIT 1;
    SELECT id INTO u3 FROM users WHERE email = 'priya.iyer@iisc.ac.in' LIMIT 1;

    IF ds252_id IS NOT NULL AND u1 IS NOT NULL THEN
        INSERT INTO course_feedback (course_id, author_id, content, is_anonymous, created_at, updated_at) VALUES
            (ds252_id, u1, 'Excellent course! Hands-on labs with serverless AWS Lambda, Terraform, and API Gateway gave solid real-world cloud engineering experience. Start the assignments early.', false, now() - interval '60 days', now() - interval '60 days'),
            (ds252_id, u2, 'Yogesh Simmhan explains distributed systems concepts such as CAP theorem, consensus, and storage hierarchies with great clarity. The project requires good teamwork.', false, now() - interval '45 days', now() - interval '45 days'),
            (ds252_id, u3, 'The lab assignments take significant time to debug, especially VPC networking and IAM permissions. Form study groups and test small increments frequently.', false, now() - interval '30 days', now() - interval '30 days')
        ON CONFLICT DO NOTHING;
    END IF;
END $$;

-- 10. Placement Hub Companies (FR-15, FR-16, FR-17)
INSERT INTO companies (name, description) VALUES
    ('Google', 'Global technology leader specializing in search, cloud computing, software, and AI.'),
    ('Microsoft', 'Multinational technology company producing computer software, cloud solutions (Azure), and personal computers.'),
    ('Amazon', 'E-commerce, cloud computing (AWS), digital streaming, and artificial intelligence giant.'),
    ('NVIDIA', 'Pioneer of GPU-accelerated computing, AI platforms, datacenter hardware, and self-driving vehicles.'),
    ('Apple', 'Innovator in consumer electronics, computer software, and online services.'),
    ('Intel', 'World leader in semiconductor design, microprocessor manufacturing, and silicon architecture.'),
    ('Texas Instruments', 'Global semiconductor company designing and manufacturing analog and embedded processing chips.'),
    ('Uber', 'Mobility and logistics technology platform operating global ride-hailing and food delivery networks.')
ON CONFLICT (name_key) DO NOTHING;

