-- Real data every CampusHub database starts with (not dummy data). docker compose loads it after
-- schema.sql on a brand-new volume; for an existing database run it once by hand (see
-- db/migrations/006_taking_it_further.sql). Running it twice adds nothing.
--
-- Campus services shown on the landing page. Links checked against iisc.ac.in and
-- healthcentre.iisc.ac.in on 24 Oct 2026; the admin edits them with PATCH /campus-services/{id}.
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
