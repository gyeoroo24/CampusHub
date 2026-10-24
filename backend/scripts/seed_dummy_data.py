"""Fill the local database with realistic dummy data for demos and manual testing.

    cd backend
    python scripts/seed_dummy_data.py            # add the dummy data (once)
    python scripts/seed_dummy_data.py --reset    # remove what this script added, then add it again
    python scripts/seed_dummy_data.py --remove   # only remove it

What it adds: ~50 students, departments and courses (CDS courses from
https://cds.iisc.ac.in/courses/descriptions/ plus a few CSA / EE / ECE ones), three years of
course feedback, materials (small placeholder PDFs uploaded to MinIO), forum threads, Buy & Sell
listings, Wanted posts, saved searches, Lost & Found reports, companies with placement records
and interview experiences, events, bookmarks, reports for the moderation queue, notifications
and chat messages.

Every dummy user has an email from SEED_USERS and signs in like any dev user, e.g.
    X-Dev-User: ananya.rao@iisc.ac.in
Existing rows (your own test users and posts) are left alone. The output is the same on every
run (fixed random seed). Reads the database URL and MinIO settings from backend/.env.
"""
import argparse
import asyncio
import json
import os
import random
import sys
import uuid
from datetime import datetime, timedelta, timezone
from decimal import Decimal
from pathlib import Path
from zoneinfo import ZoneInfo

import asyncpg
import boto3
from botocore.config import Config
from dotenv import dotenv_values

BACKEND = Path(__file__).resolve().parents[1]
ENV = {**dotenv_values(BACKEND / ".env")}
DB_URL = os.environ.get("CAMPUSHUB_DATABASE_URL") or ENV.get("CAMPUSHUB_DATABASE_URL", "postgresql://campushub:campushub@localhost:5432/campushub")
IST = ZoneInfo("Asia/Kolkata")
NOW = datetime.now(timezone.utc)
rng = random.Random(252)

# ---------------------------------------------------------------- people
FIRST = ["Ananya", "Rohan", "Priya", "Arjun", "Sneha", "Karthik", "Meera", "Aditya", "Divya", "Siddharth",
         "Kavya", "Rahul", "Ishita", "Vikram", "Nandini", "Harsh", "Pooja", "Abhinav", "Lakshmi", "Varun",
         "Shreya", "Nikhil", "Aishwarya", "Manish", "Ritika", "Sai", "Tanvi", "Pranav", "Deepika", "Aman",
         "Gayatri", "Yash", "Bhavana", "Kunal", "Swathi", "Arnav", "Neha", "Tejas", "Fatima", "Imran",
         "Joel", "Zoya", "Sanjay", "Ankita", "Ravi", "Mahima", "Dev", "Keerthana", "Omkar", "Simran"]
LAST = ["Rao", "Sharma", "Iyer", "Nair", "Reddy", "Menon", "Gupta", "Kulkarni", "Patel", "Das",
        "Bhat", "Verma", "Joshi", "Pillai", "Hegde", "Singh", "Mishra", "Chatterjee", "Shetty", "Kumar",
        "Banerjee", "Agarwal", "Krishnan", "Mukherjee", "Naidu", "Desai", "Saxena", "Ghosh", "Varghese", "Pandey",
        "Raman", "Jain", "Bose", "Murthy", "Subramanian", "Chopra", "Mehta", "Prasad", "Khan", "Ahmed",
        "Thomas", "Qureshi", "Venkatesh", "Sinha", "Shankar", "Kapoor", "Malhotra", "Gowda", "Patil", "Kaur"]
PROGRAMMES = {
    "Computational and Data Sciences": ["M.Tech (CDS)", "M.Tech (Research) CDS", "PhD CDS"],
    "Computer Science and Automation": ["M.Tech CSA", "M.Tech (AI)", "PhD CSA"],
    "Electrical Engineering": ["M.Tech (Signal Processing)", "PhD EE"],
    "Electrical Communication Engineering": ["M.Tech (Telecom)", "PhD ECE"],
    "Mathematics": ["Int. PhD Mathematics"],
    "Undergraduate Programme": ["BS (Research)"],
}


def _seed_users() -> list[dict]:
    users = []
    depts = list(PROGRAMMES)
    weights = [10, 6, 3, 3, 1, 3]
    for i, (first, last) in enumerate(zip(FIRST, LAST)):
        dept = rng.choices(depts, weights)[0]
        alum = i in (47, 48)          # two alumni accounts (alum.iisc.ac.in passes sign-up)
        users.append({
            "email": f"{first.lower()}.{last.lower()}@{'alum.' if alum else ''}iisc.ac.in",
            "name": f"{first} {last}",
            "department": dept,
            "programme": rng.choice(PROGRAMMES[dept]),
            "graduation_year": rng.choice([2022, 2023]) if alum else rng.choice([2026, 2027, 2027, 2028, 2029]),
            "phone": f"+91{rng.randint(70000, 99999)}{rng.randint(10000, 99999)}" if rng.random() < 0.6 else None,
        })
    return users


SEED_USERS = _seed_users()
SEED_EMAILS = [u["email"] for u in SEED_USERS]

# ---------------------------------------------------------------- academics
# (code, name, instructor, term, topics). Term = semester the course runs in: Aug (Aug–Dec) or Jan (Jan–Apr).
CDS = [
    ("DS 200", "Research Methods", "CDS faculty", "Aug", ["literature review", "technical writing", "presentations"]),
    ("DS 201", "Bioinformatics", "K. Sekar and D. Pal", "Jan", ["sequence alignment", "protein structure", "phylogenetics"]),
    ("DS 202", "Algorithmic Foundations of Big Data Biology", "Chirag Jain", "Jan", ["genome indexing", "string matching", "genome assembly"]),
    ("DS 207", "Introduction to Natural Language Processing", "Danish Pruthi", "Aug", ["language models", "text classification", "conditioned generation"]),
    ("DS 211", "Numerical Optimization", "Deepak Subramani", "Aug", ["constrained optimization", "dynamic programming", "optimal control"]),
    ("DS 215", "Introduction to Data Science", "Anirban Chakraborty", "Aug", ["hypothesis testing", "parameter estimation", "regression"]),
    ("DS 216", "Machine Learning for Data Science", "Vaanathi Sundaresan", "Jan", ["dimensionality reduction", "deep learning basics", "significance testing"]),
    ("DS 221", "Introduction to Scalable Systems", "Matthew Jacob, Sathish Vadhiyar, Chirag Jain", "Aug", ["OpenMP", "MPI", "CUDA"]),
    ("DS 222", "Machine Learning with Large Datasets", "P P Talukdar", "Aug", ["scalable SGD", "sketching", "matrix factorization"]),
    ("DS 226", "Introduction to Computing for AI & Machine Learning", "Sashikumaar Ganesan", "Aug", ["Python OOP", "NumPy", "TensorFlow"]),
    ("DS 244", "Hardware-aware Scientific Computing", "Sashikumaar Ganesan", "Jan", ["hybrid programming", "performance analysis", "sparse linear algebra"]),
    ("DS 250", "Multigrid Methods", "Sashikumaar Ganesan", "Jan", ["Krylov solvers", "algebraic multigrid", "multigrid cycles"]),
    ("DS 252", "Cloud Computing", "Yogesh Simmhan", "Aug", ["virtualization", "serverless execution models", "the CAP theorem"]),
    ("DS 255", "System Virtualization", "J. Lakshmi", "Jan", ["hypervisors", "memory virtualization", "containers"]),
    ("DS 256", "Scalable Systems for Data Science", "Yogesh Simmhan", "Jan", ["MapReduce", "Spark", "vertex-centric graph processing"]),
    ("DS 260", "Medical Imaging", "Phaneendra Yalavarthy", "Aug", ["CT reconstruction", "MRI physics", "ultrasound"]),
    ("DS 261", "Artificial Intelligence for Medical Image Analysis", "Vaanathi Sundaresan", "Jan", ["segmentation", "evaluation metrics", "deployment"]),
    ("DS 263", "Video Analytics", "R. Venkatesh Babu, Anirban Chakraborty, Arjun Jain", "Jan", ["object tracking", "activity recognition", "anomaly detection"]),
    ("DS 265", "Deep Learning for Computer Vision", "R. Venkatesh Babu, Anirban Chakraborty", "Aug", ["CNNs", "RNNs", "GANs"]),
    ("DS 269", "Computational Methods for Reacting Flows", "Aditya Konduri", "Jan", ["chemical kinetics", "reacting-flow solvers", "dimensionality reduction"]),
    ("DS 284", "Numerical Linear Algebra", "Phani Motamarri", "Aug", ["SVD", "QR and LU", "Krylov subspace methods"]),
    ("DS 285", "Tensor Computations for Data Science", "Ratikanta Behera", "Jan", ["CP decomposition", "Tucker decomposition", "tensor trains"]),
    ("DS 288", "Numerical Methods", "Ratikanta Behera", "Aug", ["root finding", "interpolation", "numerical integration"]),
    ("DS 289", "Numerical Solution of Differential Equations", "Aditya Konduri", "Jan", ["stability analysis", "finite elements", "PDE solvers"]),
    ("DS 290", "Modelling and Simulation", "Soumyendu Raha", "Aug", ["Monte Carlo", "Markov chains", "discrete-event simulation"]),
    ("DS 291", "Finite Elements: Theory and Algorithms", "Sashikumaar Ganesan", "Aug", ["weak formulations", "Sobolev spaces", "error analysis"]),
    ("DS 294", "Data Analysis and Visualization", "Anirban Chakraborty", "Jan", ["visualization pipelines", "volume rendering", "PCA"]),
    ("DS 295", "Parallel Programming", "Sathish Vadhiyar", "Jan", ["advanced MPI", "GPU computing", "parallel algorithms"]),
    ("DS 298", "Random Variates in Computation", "Murugesan Venkatapathi", "Jan", ["random variate generation", "randomized linear algebra", "MCMC"]),
    ("DS 299", "Dissertation Project", "Thesis advisor", "Aug", ["problem definition", "evaluation", "the thesis write-up"]),
    ("DS 303", "Chemoinformatics", "Debnath Pal", "Jan", ["chemical databases", "molecular simulation", "similarity search"]),
    ("DS 305", "Topics in Web-scale Knowledge Harvesting", "P P Talukdar", "Jan", ["relation extraction", "knowledge base construction", "open IE"]),
    ("DS 307", "Ethics in AI", "Danish Pruthi", "Jan", ["fairness", "privacy", "AI policy"]),
    ("DS 323", "Parallel Computing for Finite Element Methods", "Sashikumaar Ganesan", "Jan", ["parallel data structures", "geometric multigrid", "ParMooN"]),
    ("DS 360", "Topics in Medical Imaging", "Phaneendra K Yalavarthy", "Jan", ["GPU reconstruction", "image registration", "optical tomography"]),
    ("DS 363", "Topics in Visual Analytics", "Anirban Chakraborty, R. Venkatesh Babu", "Aug", ["vision-language models", "domain adaptation", "generative models"]),
    ("DS 391", "Data Assimilation to Dynamical Systems", "Soumyendu Raha", "Jan", ["Kalman filtering", "particle filters", "state estimation"]),
    ("DS 392", "Environmental Data Analytics", "Deepak Subramani", "Jan", ["remote sensing", "Bayesian inference", "ocean sensing"]),
    ("DS 393", "High-performance Computing for Quantum Modeling of Materials", "Phani Motamarri", "Jan", ["DFT", "eigensolvers", "SCF mixing"]),
    ("DS 394", "Scientific Computing with Quantum Algorithms", "Phani Motamarri", "Aug", ["phase estimation", "HHL", "quantum linear algebra"]),
    ("DS 397", "Topics in Embedded Computing", "S K Nandy", "Jan", ["dataflow architectures", "CGRAs", "compiler techniques"]),
]
OTHER_COURSES = {
    "Computer Science and Automation": [
        ("E0 225", "Design and Analysis of Algorithms", "CSA faculty", "Aug", ["greedy algorithms", "dynamic programming", "NP-completeness"]),
        ("E0 243", "Computer Architecture", "CSA faculty", "Aug", ["pipelining", "cache hierarchies", "out-of-order execution"]),
        ("E0 253", "Operating Systems", "CSA faculty", "Jan", ["scheduling", "virtual memory", "file systems"]),
        ("E0 270", "Machine Learning", "CSA faculty", "Jan", ["SVMs", "kernel methods", "neural networks"]),
        ("E0 256", "Computer Systems Security", "CSA faculty", "Jan", ["memory safety", "side channels", "network attacks"]),
    ],
    "Electrical Engineering": [
        ("E1 213", "Pattern Recognition and Neural Networks", "EE faculty", "Jan", ["Bayes classifiers", "backpropagation", "kernel methods"]),
        ("E9 241", "Digital Image Processing", "EE faculty", "Aug", ["image transforms", "restoration", "segmentation"]),
    ],
    "Electrical Communication Engineering": [
        ("E2 202", "Random Processes", "ECE faculty", "Aug", ["stationarity", "Markov chains", "Gaussian processes"]),
        ("E2 211", "Digital Communication", "ECE faculty", "Jan", ["modulation", "detection theory", "channel coding"]),
    ],
    "Mathematics": [
        ("MA 221", "Linear Algebra", "Mathematics faculty", "Aug", ["vector spaces", "eigenvalues", "canonical forms"]),
    ],
}

POSITIVE = [
    "One of the best courses I took at IISc.",
    "{instructor} explains {topic} really clearly.",
    "Loved this course, especially the part on {topic}.",
    "Very well organised: lectures, slides and assignments all line up.",
    "The assignments on {topic} taught me more than any textbook.",
    "Great course if you want a solid base in {topic}.",
    "TAs were responsive and office hours were genuinely useful.",
]
NEGATIVE = [
    "The pace was brutal, especially around {topic}.",
    "Lectures felt disconnected from the assignments.",
    "Grading was opaque and marks came back very late.",
    "Too much content crammed into one semester; {topic} got two rushed lectures.",
    "Assignment specs kept changing a few days before the deadline.",
    "Hard to follow unless you already know {topic} well.",
]
MIXED = [
    "Content is great but the workload is heavy.",
    "{topic} was interesting, the rest felt a bit rushed.",
    "Good course overall, though the second half drags.",
    "Useful material on {topic}, but the evaluation is uneven.",
]
WORKLOAD = {
    "light": ["Workload is manageable alongside a TA job.", "About 5-7 hours a week outside class.",
              "Never felt overloaded, even in exam week."],
    "medium": ["Expect around 8-10 hours a week outside class.", "Two assignments overlap with midsems, plan ahead.",
               "Doable with one other heavy course, not two."],
    "heavy": ["Expect 12+ hours a week; the assignments are long.", "Do not take this with two other lab courses.",
              "The project alone ate my weekends for a month."],
}
EXAMS = [
    "The midterm was fair if you did the assignments.",
    "Final exam was much harder than the practice papers.",
    "Open-notes exams, but you need to really understand {topic}.",
    "Quizzes every two weeks keep you on track.",
    "Grading is mostly assignments and a project, the exam is a small part.",
]
ADVICE = [
    "Brush up on linear algebra before joining.",
    "Start the project early.",
    "Attend the TA sessions, they help a lot.",
    "Form a study group in the first week.",
    "Python and NumPy are assumed from day one.",
    "Read the reference papers before each lecture; it makes a big difference.",
    "Revise {topic} before the course starts.",
]
TRAJECTORIES = ["improving", "declining", "stable_good", "mixed", "stable_good", "improving"]

# ---------------------------------------------------------------- campus places
HOSTELS = ["N Block hostel", "Kabini hostel", "Bhadra hostel", "Tunga hostel", "Sharavati hostel",
           "C Block hostel", "D Block hostel", "Married Research Scholars' quarters"]
PLACES = ["JRD Tata Memorial Library", "CDS building", "CSA department", "ECE department", "Main Building",
          "Students' Gymkhana", "Prakruthi", "Nesara", "A mess", "C mess", "Kabini mess", "Faculty Hall",
          "J N Tata Auditorium", "Health Centre", "Swimming pool", "Football ground", "Main gate bus stop",
          "Tata Book House", "Old Physics building", "Biological Sciences building"]

# ---------------------------------------------------------------- buy & sell
LISTING_ITEMS = {
    "Cycles": [("Hero Sprint 26T cycle", "Single speed, new tyres last month, lock included.", 2200, 3800),
               ("Btwin Rockrider ST20", "7 gears, front suspension, minor scratches.", 4500, 7500),
               ("Hercules Roadeo A50", "21 gears, disc brakes, serviced in September.", 5000, 8500),
               ("Atlas Lady Bird cycle", "Basket and stand included, good for campus rides.", 1500, 2800),
               ("Firefox Bad Attitude 26T", "Lightweight frame, rear brake needs tightening.", 3500, 6000),
               ("Old Hero Jet cycle", "Works fine, chain a bit rusty. Cheap for a first-year.", 1200, 2000)],
    "Books": [("Introduction to Algorithms (CLRS), 3rd ed", "Hardcover, a few pencil notes.", 600, 1200),
              ("Convex Optimization - Boyd & Vandenberghe", "Printed copy, clean.", 400, 800),
              ("Pattern Recognition and ML - Bishop", "Indian edition, like new.", 500, 900),
              ("Computer Architecture - Hennessy & Patterson", "6th edition, great for E0 243.", 700, 1300),
              ("Linear Algebra and Its Applications - Strang", "4th edition.", 300, 600),
              ("Deep Learning - Goodfellow et al.", "Hardcover, like new.", 1200, 2200),
              ("GATE CS previous papers bundle", "2015-2024 solved papers.", 200, 450)],
    "Electronics": [("Dell 24-inch monitor (P2419H)", "IPS, HDMI cable included.", 6000, 9500),
                    ("Logitech MK270 keyboard and mouse", "Wireless combo, batteries included.", 700, 1200),
                    ("Raspberry Pi 4 (4GB) kit", "Case, fan and 32GB card.", 3500, 5000),
                    ("Casio fx-991ES Plus calculator", "Allowed in most exams.", 500, 900),
                    ("TP-Link Archer C6 router", "Works great in hostel rooms.", 900, 1500),
                    ("Sony WH-CH520 headphones", "Bluetooth, 6 months old.", 1800, 2800),
                    ("Laptop stand (aluminium)", "Adjustable height.", 500, 900),
                    ("Extension board with surge protection", "6 sockets, 3m cable.", 300, 500)],
    "Furniture": [("Study table with drawer", "Fits hostel rooms, pick up only.", 1500, 3000),
                  ("Ergonomic office chair", "Adjustable armrests and lumbar support.", 2500, 5000),
                  ("Bookshelf (4 tier)", "Engineered wood.", 800, 1500),
                  ("Single-bed mattress (Sleepwell)", "Used one year, clean.", 1500, 2800)],
    "Kitchen & Appliances": [("Prestige induction cooktop", "Works perfectly, with one pan.", 1200, 2000),
                             ("Electric kettle 1.5L", "Steel, auto shut-off.", 400, 700),
                             ("Mini fridge (Haier 50L)", "Moving out, must go this week.", 4500, 7000),
                             ("Rice cooker 1.8L", "Barely used.", 900, 1500),
                             ("Room cooler (Bajaj)", "Great for summer in the hostel.", 2500, 4500)],
    "Sports & Fitness": [("Yonex Muscle Power badminton racquet", "With cover, strung recently.", 900, 1600),
                         ("SG cricket bat (English willow)", "Knocked in, used one season.", 2500, 4500),
                         ("Nivia football (size 5)", "Lightly used.", 400, 700),
                         ("Yoga mat 6mm", "With carry strap.", 300, 600),
                         ("Dumbbell set 2 x 5kg", "Rubber coated.", 900, 1500)],
    "Clothing": [("Winter jacket (M)", "For the Himalayan trek or Delhi winters.", 900, 1800),
                 ("Lab coat (L)", "Used for one lab course, washed.", 200, 350),
                 ("Formal blazer (40)", "Worn twice, good for placement interviews.", 1500, 3000)],
    "Stationery": [("Drafting kit and A2 drawing board", "Complete set.", 400, 800),
                   ("Pack of 10 long notebooks", "Unused.", 250, 400)],
}

# ---------------------------------------------------------------- lost & found
LF_ITEMS = {
    "ID card": ["IISc ID card in a blue lanyard", "Student ID card with a red holder", "ID card and a library card clipped together"],
    "Water bottle": ["Steel Milton bottle with stickers", "Black insulated bottle, 1L", "Blue Tupperware bottle"],
    "Earbuds": ["White earbuds in a charging case", "boAt Airdopes, black case", "OnePlus Buds, case only"],
    "Umbrella": ["Black foldable umbrella", "Large blue golf umbrella", "Red umbrella with a wooden handle"],
    "Wallet": ["Brown leather wallet with some cash", "Black wallet, no cash, has a metro card", "Small card holder, grey"],
    "Keys": ["Bunch of 3 keys with a Kabini hostel tag", "Cycle lock key on a green keychain", "Lab key with a CDS tag"],
    "Laptop charger": ["Dell 65W charger", "MacBook USB-C charger with cable", "Lenovo charger, round pin"],
    "Spectacles": ["Black frame spectacles in a brown case", "Rimless spectacles, no case"],
    "Calculator": ["Casio fx-991ES with name written on the back", "Casio fx-82MS"],
    "Jacket": ["Grey hoodie (L)", "Navy blue windcheater"],
    "Notebook": ["Blue notebook with DS 252 notes", "Spiral notebook full of numerical methods notes"],
}

COMPANIES = [
    ("Google", "Search, cloud and AI products.", ["Software Engineer", "Research Engineer"]),
    ("Microsoft", "Cloud, productivity and AI.", ["Software Engineer", "Data Scientist"]),
    ("Amazon", "E-commerce and AWS.", ["SDE", "Applied Scientist"]),
    ("NVIDIA", "GPUs and accelerated computing.", ["Deep Learning Engineer", "GPU Architect"]),
    ("Qualcomm", "Wireless and mobile chipsets.", ["Systems Engineer", "ML Engineer"]),
    ("Goldman Sachs", "Investment banking and securities.", ["Quant Strategist", "Analyst"]),
    ("JP Morgan Chase", "Financial services.", ["Quantitative Researcher", "Software Engineer"]),
    ("Texas Instruments", "Analog and embedded processing.", ["Digital Design Engineer", "Analog Design Engineer"]),
    ("Intel", "Processors and platforms.", ["Graphics Software Engineer", "Performance Engineer"]),
    ("Samsung R&D Bangalore", "Research for mobile and devices.", ["Engineer", "Lead Engineer"]),
    ("Adobe", "Creative and document software.", ["Member of Technical Staff", "Research Engineer"]),
    ("Walmart Global Tech", "Retail technology.", ["Data Scientist", "Software Engineer"]),
    ("Arista Networks", "Cloud networking.", ["Software Engineer"]),
    ("Tower Research Capital", "High-frequency trading.", ["Core Engineer", "Quant Researcher"]),
    ("Flipkart", "E-commerce.", ["SDE", "Data Scientist"]),
]
DSA = ["two pointers on a sorted array", "LRU cache design", "top-k frequent elements", "binary search on the answer",
       "shortest path with Dijkstra", "longest increasing subsequence", "merge intervals", "trie for autocomplete",
       "detect a cycle in a directed graph", "sliding window maximum"]
TECH = ["bias-variance trade-off", "how gradient descent converges", "virtual memory and TLBs", "cache coherence",
        "designing a URL shortener", "probability puzzles", "CUDA thread blocks and warps", "SQL joins and indexes",
        "transformer attention", "MapReduce vs Spark", "consistent hashing", "options pricing basics"]

EVENT_TAGS = ["Sports", "Culture", "Food/Mess", "Nature", "Photography", "Tech Talks", "Music", "Workshops"]
EVENTS = [
    ("CDS Seminar: Serverless at scale", "Tech Talks", "CDS seminar hall", "A talk on cold starts and cost at scale."),
    ("Bird walk around the campus", "Nature", "Main gate", "Spot over 40 species on a 2-hour morning walk. Binoculars available."),
    ("Inter-hostel cricket league", "Sports", "Gymkhana ground", "Teams of 11 from every hostel. Register by Friday."),
    ("Diwali night at the Gymkhana", "Culture", "Students' Gymkhana", "Rangoli, food stalls and music."),
    ("Photography walk: heritage buildings", "Photography", "Main Building", "Golden-hour walk; phones welcome."),
    ("Music club open jam", "Music", "Students' Gymkhana", "Bring an instrument or just listen."),
    ("Hands-on workshop: Terraform on AWS", "Workshops", "CDS 102", "Build and tear down a VPC in 90 minutes."),
    ("Mess food feedback open house", "Food/Mess", "C mess", "Talk to the mess committee about the menu."),
    ("Pravega 2027 volunteers meet", "Culture", "Faculty Hall", "Planning meet for the annual science and cultural fest."),
    ("Badminton doubles tournament", "Sports", "Gymkhana indoor courts", "Mixed doubles, knockout format."),
    ("Talk: careers in quant finance", "Tech Talks", "J N Tata Auditorium", "Alumni from trading firms share their journeys."),
    ("Night sky watching", "Nature", "Football ground", "Telescopes from the astronomy club."),
    ("Kannada Rajyotsava cultural evening", "Culture", "J N Tata Auditorium", "Dance, music and theatre."),
    ("Workshop: writing your first paper", "Workshops", "JRD Tata Memorial Library", "Structure, figures and the review process."),
    ("Campus cyclothon", "Sports", "Main gate", "10 km loop around the campus. Cycles available on request."),
]


def pdf_bytes(title: str) -> bytes:
    """A one-page PDF with a single line of text (placeholder for a course material)."""
    text = title.replace("\\", "").replace("(", "").replace(")", "")[:80]
    stream = f"BT /F1 18 Tf 72 720 Td ({text}) Tj ET".encode()
    objs = [b"<< /Type /Catalog /Pages 2 0 R >>",
            b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R "
            b"/Resources << /Font << /F1 5 0 R >> >> >>",
            b"<< /Length %d >>\nstream\n" % len(stream) + stream + b"\nendstream",
            b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"]
    out, offsets = bytearray(b"%PDF-1.4\n"), []
    for i, obj in enumerate(objs, start=1):
        offsets.append(len(out))
        out += b"%d 0 obj\n" % i + obj + b"\nendobj\n"
    xref = len(out)
    out += b"xref\n0 %d\n0000000000 65535 f \n" % (len(objs) + 1)
    out += b"".join(b"%010d 00000 n \n" % o for o in offsets)
    out += b"trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (len(objs) + 1, xref)
    return bytes(out)


def s3_client():
    return boto3.client("s3", endpoint_url=ENV.get("CAMPUSHUB_S3_ENDPOINT_URL") or "http://localhost:9000",
                        region_name=ENV.get("CAMPUSHUB_S3_REGION", "ap-south-1"),
                        aws_access_key_id=ENV.get("AWS_ACCESS_KEY_ID", "minioadmin"),
                        aws_secret_access_key=ENV.get("AWS_SECRET_ACCESS_KEY", "minioadmin"),
                        config=Config(signature_version="s3v4", connect_timeout=5, retries={"max_attempts": 2}))


def at(year: int, month: int, day: int, hour: int = 12) -> datetime:
    return datetime(year, month, day, hour, rng.randint(0, 59), tzinfo=IST)


def days_ago(lo: float, hi: float) -> datetime:
    return NOW - timedelta(days=rng.uniform(lo, hi))


def semesters(term: str) -> list[tuple[str, datetime, datetime]]:
    """Past offerings of a course: (label, window start, window end) for when feedback was written."""
    if term == "Aug":
        out = [(f"Aug {y}", at(y, 11, 15), at(y, 12, 20)) for y in (2023, 2024, 2025)]
        out.append(("Aug 2026", at(2026, 9, 20), at(2026, 10, 20)))    # running now: a few mid-semester notes
        return out
    return [(f"Jan {y}", at(y, 4, 10), at(y, 5, 20)) for y in (2024, 2025, 2026)]


def between(a: datetime, b: datetime) -> datetime:
    return a + (b - a) * rng.random()


def feedback_text(course: tuple, score: float, workload: str) -> str:
    _, _, instructor, _, topics = course
    fill = lambda s: s.format(instructor=instructor.split(",")[0], topic=rng.choice(topics))  # noqa: E731
    pool = POSITIVE if score > 0.3 else NEGATIVE if score < -0.3 else MIXED
    parts = [fill(rng.choice(pool))]
    if rng.random() < 0.8:
        parts.append(rng.choice(WORKLOAD[workload]))
    if rng.random() < 0.6:
        parts.append(fill(rng.choice(EXAMS)))
    if rng.random() < 0.6:
        parts.append(fill(rng.choice(ADVICE)))
    return " ".join(parts)


def trajectory_score(kind: str, i: int, n: int) -> float:
    step = i / max(n - 1, 1)
    base = {"improving": -0.5 + 1.1 * step, "declining": 0.6 - 1.1 * step,
            "stable_good": 0.55, "mixed": 0.0}[kind]
    return max(-1.0, min(1.0, base + rng.gauss(0, 0.35)))


# ---------------------------------------------------------------- removal
async def remove_seed(conn: asyncpg.Connection) -> list[str]:
    """Delete everything owned by the dummy users. Returns S3 keys of their course materials."""
    ids = [r["id"] for r in await conn.fetch("SELECT id FROM users WHERE email::text = ANY($1::text[])", SEED_EMAILS)]
    if not ids:
        return []
    keys = [r["file_s3_key"] for r in await conn.fetch(
        "SELECT file_s3_key FROM course_materials WHERE uploaded_by = ANY($1::uuid[])", ids)]
    listing_ids = [r["id"] for r in await conn.fetch("SELECT id FROM listings WHERE seller_id = ANY($1::uuid[])", ids)]
    event_ids = [r["id"] for r in await conn.fetch("SELECT id FROM events WHERE created_by = ANY($1::uuid[])", ids)]
    imports = [r["id"] for r in await conn.fetch(
        "SELECT id FROM placement_bulk_imports WHERE moderator_id = ANY($1::uuid[])", ids)]
    statements = [
        ("DELETE FROM bookmarks WHERE target_id = ANY($1::uuid[])", listing_ids + event_ids),
        ("DELETE FROM reports WHERE reporter_id = ANY($1::uuid[]) OR handled_by = ANY($1::uuid[])", ids),
        ("DELETE FROM moderation_log WHERE moderator_id = ANY($1::uuid[])", ids),
        ("DELETE FROM chat_messages WHERE sender_id = ANY($1::uuid[]) OR receiver_id = ANY($1::uuid[])", ids),
        ("DELETE FROM events WHERE created_by = ANY($1::uuid[])", ids),
        ("DELETE FROM comments WHERE user_id = ANY($1::uuid[])", ids),
        ("DELETE FROM threads WHERE author_id = ANY($1::uuid[])", ids),
        ("DELETE FROM course_feedback WHERE author_id = ANY($1::uuid[])", ids),
        ("DELETE FROM course_materials WHERE uploaded_by = ANY($1::uuid[])", ids),
        ("DELETE FROM interview_experiences WHERE author_id = ANY($1::uuid[])", ids),
        ("DELETE FROM placement_records WHERE import_id = ANY($1::uuid[])", imports),
        ("DELETE FROM placement_bulk_imports WHERE id = ANY($1::uuid[])", imports),
        ("DELETE FROM wanted_posts WHERE author_id = ANY($1::uuid[])", ids),
        ("DELETE FROM listings WHERE seller_id = ANY($1::uuid[])", ids),
        ("DELETE FROM lost_reports WHERE reporter_id = ANY($1::uuid[])", ids),
        ("DELETE FROM found_reports WHERE reporter_id = ANY($1::uuid[])", ids),
        ("DELETE FROM moderator_assignments WHERE user_id = ANY($1::uuid[]) OR granted_by = ANY($1::uuid[]) "
         "OR revoked_by = ANY($1::uuid[])", ids),
        # Categories a dummy user created stay (other posts may use them); just drop the link.
        ("UPDATE bs_categories SET created_by = NULL WHERE created_by = ANY($1::uuid[])", ids),
        ("UPDATE lf_categories SET created_by = NULL WHERE created_by = ANY($1::uuid[])", ids),
        ("DELETE FROM users WHERE id = ANY($1::uuid[])", ids),
    ]
    for sql, arg in statements:
        await conn.execute(sql, arg)
    # Forums left without any thread were only created for the dummy data.
    await conn.execute("DELETE FROM forums f WHERE NOT EXISTS (SELECT 1 FROM threads t WHERE t.forum_id = f.id)")
    return keys


# ---------------------------------------------------------------- seeding
async def seed(conn: asyncpg.Connection, s3, bucket: str) -> dict:
    counts: dict[str, int] = {}

    # departments and courses (shared reference data: added if missing, never removed)
    dept_ids = {}
    for name in PROGRAMMES:
        await conn.execute("INSERT INTO departments (name) VALUES ($1) ON CONFLICT (name) DO NOTHING", name)
        dept_ids[name] = await conn.fetchval("SELECT id FROM departments WHERE name = $1", name)
    all_courses = [("Computational and Data Sciences", c) for c in CDS] + \
                  [(d, c) for d, cs in OTHER_COURSES.items() for c in cs]
    course_ids = {}
    for dept, c in all_courses:
        await conn.execute("INSERT INTO courses (department_id, code, name) VALUES ($1, $2, $3) "
                           "ON CONFLICT (department_id, code) DO NOTHING", dept_ids[dept], c[0], c[1])
        course_ids[c[0]] = await conn.fetchval(
            "SELECT id FROM courses WHERE department_id = $1 AND code = $2", dept_ids[dept], c[0])
    counts["courses"] = len(course_ids)

    # users
    uid = {}
    for u in SEED_USERS:
        uid[u["email"]] = await conn.fetchval(
            """INSERT INTO users (cognito_sub, email, name, phone, department_id, programme, graduation_year, created_at)
               VALUES ($1, $2, $3, $4, $5, $6, $7, $8) RETURNING id""",
            f"dev|{u['email']}", u["email"], u["name"], u["phone"], dept_ids[u["department"]], u["programme"],
            u["graduation_year"], days_ago(60, 400))
    users = list(uid.values())
    students = users[:47]
    counts["users"] = len(users)
    by_dept = {d: [uid[u["email"]] for u in SEED_USERS if u["department"] == d] for d in PROGRAMMES}

    # admin: keep the existing one; on an empty database make the first dummy user admin
    admin = await conn.fetchval("SELECT id FROM users WHERE base_role = 'admin'")
    if admin is None:
        admin = users[0]
        await conn.execute("UPDATE users SET base_role = 'admin' WHERE id = $1", admin)

    # moderators
    mods = {"buy_sell": users[1], "lost_found": users[2], "placement_hub": users[3]}
    for module, user in mods.items():
        await conn.execute("INSERT INTO moderator_assignments (user_id, module, granted_by) VALUES ($1, $2, $3)",
                           user, module, admin)
    cds_mod, ds252_mod = users[4], users[5]
    await conn.execute("""INSERT INTO moderator_assignments (user_id, module, scope_type, department_id, granted_by)
                          VALUES ($1, 'academic_help', 'department', $2, $3)""",
                       cds_mod, dept_ids["Computational and Data Sciences"], admin)
    await conn.execute("""INSERT INTO moderator_assignments (user_id, module, scope_type, course_id, granted_by)
                          VALUES ($1, 'academic_help', 'course', $2, $3)""", ds252_mod, course_ids["DS 252"], cds_mod)
    counts["moderator grants"] = 5

    # course feedback: every past offering, sentiment following a per-course trajectory
    fb_rows = []
    for dept, course in all_courses:
        is_cds = dept == "Computational and Data Sciences"
        kind = rng.choice(TRAJECTORIES)
        workload = rng.choice(["light", "medium", "medium", "heavy"])
        offerings = semesters(course[3])
        pool = by_dept[dept] + students if is_cds else by_dept.get(dept, []) + students
        for i, (_, start, end) in enumerate(offerings):
            ongoing = start > NOW - timedelta(days=60)
            n = rng.randint(1, 3) if ongoing else rng.randint(4, 9) if is_cds else rng.randint(2, 4)
            for author in rng.sample(pool, k=min(n, len(pool))):
                score = trajectory_score(kind, i, len(offerings))
                created = min(between(start, end), NOW - timedelta(hours=2))
                fb_rows.append((course_ids[course[0]], author, feedback_text(course, score, workload), created))
    await conn.executemany(
        "INSERT INTO course_feedback (course_id, author_id, content, created_at, updated_at) VALUES ($1, $2, $3, $4, $4)",
        fb_rows)
    counts["course feedback"] = len(fb_rows)

    # course materials: placeholder PDFs in MinIO
    material_kinds = [("Lecture notes", "notes"), ("Slides, weeks 1-4", "slides"), ("Assignment 1", "past_assignment"),
                      ("Midterm paper", "exam_material"), ("Final exam paper", "exam_material")]
    mat_rows = []
    for dept, course in all_courses:
        uploader = cds_mod if dept == "Computational and Data Sciences" else admin
        if course[0] == "DS 252":
            uploader = ds252_mod
        for title, mtype in rng.sample(material_kinds, k=rng.randint(1, 3)):
            year = rng.choice([2024, 2025])
            full = f"{course[0]} {title} ({course[3]} {year})"
            key = f"course-materials/{course_ids[course[0]]}/{uploader}/{uuid.uuid4()}.pdf"
            s3.put_object(Bucket=bucket, Key=key, Body=pdf_bytes(full), ContentType="application/pdf",
                          Tagging="attached=true")
            mat_rows.append((course_ids[course[0]], uploader, full, mtype, key, days_ago(20, 500)))
    await conn.executemany(
        """INSERT INTO course_materials (course_id, uploaded_by, title, material_type, file_s3_key, created_at, updated_at)
           VALUES ($1, $2, $3, $4, $5, $6, $6)""", mat_rows)
    counts["course materials"] = len(mat_rows)

    # forums, threads and comments
    thread_titles = [
        "Is {code} doable alongside a TA job?", "Good resources for {topic}?", "Assignment {n} clarification",
        "Study group for the {code} midsem", "Which project topics did people pick last year?",
        "Previous year papers for {code}?", "Is {topic} covered in the final exam?",
    ]
    replies = [
        "I took it last year, it's fine if you start assignments early.", "The TA posted a clarification on Teams.",
        "Check the reference papers from the first lecture, they cover most of it.",
        "Count me in for the study group.", "The library has two copies of the textbook.",
        "Last year's midsem was mostly from the assignments.", "+1, same question.",
        "Office hours on Thursday helped me with exactly this.", "I've uploaded my notes to the materials section.",
        "Doable, but avoid pairing it with another lab-heavy course.",
    ]
    popular = ["DS 252", "DS 221", "DS 211", "DS 265", "DS 222", "DS 284", "DS 256", "DS 207", "DS 295",
               "DS 288", "E0 243", "E0 270", "E0 225"]
    lookup = {c[0]: c for _, c in all_courses}
    n_threads = n_comments = 0
    notif_rows = []
    for code in popular:
        forum = await conn.fetchval("INSERT INTO forums (scope_type, course_id) VALUES ('course', $1) "
                                    "ON CONFLICT (course_id) DO UPDATE SET course_id = EXCLUDED.course_id RETURNING id",
                                    course_ids[code])
        for _ in range(rng.randint(2, 5)):
            author = rng.choice(students)
            created = days_ago(5, 300)
            title = rng.choice(thread_titles).format(code=code, topic=rng.choice(lookup[code][4]), n=rng.randint(1, 4))
            thread = await conn.fetchval(
                "INSERT INTO threads (forum_id, author_id, title, created_at, updated_at) VALUES ($1, $2, $3, $4, $4) "
                "RETURNING id", forum, author, title, created)
            await conn.execute("INSERT INTO comments (thread_id, user_id, content, created_at, updated_at) "
                               "VALUES ($1, $2, $3, $4, $4)", thread, author,
                               f"{title} Any advice from people who took {code} before?", created)
            n_threads += 1
            n_comments += 1
            t = created
            for _ in range(rng.randint(1, 6)):
                t += timedelta(hours=rng.uniform(1, 48))
                if t > NOW:
                    break
                replier = rng.choice(students)
                cid = await conn.fetchval(
                    "INSERT INTO comments (thread_id, user_id, content, created_at, updated_at) "
                    "VALUES ($1, $2, $3, $4, $4) RETURNING id", thread, replier, rng.choice(replies), t)
                n_comments += 1
                if replier != author and t > NOW - timedelta(days=25):
                    name = await conn.fetchval("SELECT name FROM users WHERE id = $1", replier)
                    notif_rows.append((author, "forum_reply", {
                        "thread_id": str(thread), "comment_id": str(cid), "forum_id": str(forum),
                        "message": f"{name} replied in “{title}”"}, rng.random() < 0.5, t))
    for dept in ("Computational and Data Sciences", "Computer Science and Automation"):
        forum = await conn.fetchval("INSERT INTO forums (scope_type, department_id) VALUES ('department', $1) "
                                    "ON CONFLICT (department_id) DO UPDATE SET department_id = EXCLUDED.department_id "
                                    "RETURNING id", dept_ids[dept])
        for title in ("Elective suggestions for next semester", "Lab access after 10 pm?", "TAship allocation thread"):
            author, created = rng.choice(students), days_ago(10, 200)
            thread = await conn.fetchval(
                "INSERT INTO threads (forum_id, author_id, title, created_at, updated_at) VALUES ($1, $2, $3, $4, $4) "
                "RETURNING id", forum, author, title, created)
            await conn.execute("INSERT INTO comments (thread_id, user_id, content, created_at, updated_at) "
                               "VALUES ($1, $2, $3, $4, $4)", thread, author, f"{title}: please share what you know.",
                               created)
            for k in range(rng.randint(2, 5)):
                await conn.execute("INSERT INTO comments (thread_id, user_id, content, created_at, updated_at) "
                                   "VALUES ($1, $2, $3, $4, $4)", thread, rng.choice(students), rng.choice(replies),
                                   created + timedelta(hours=6 * (k + 1)))
                n_comments += 1
            n_threads += 1
            n_comments += 1
    counts["threads"], counts["comments"] = n_threads, n_comments

    # buy & sell
    cat_ids = {}
    for name in LISTING_ITEMS:
        await conn.execute("INSERT INTO bs_categories (name) VALUES ($1) ON CONFLICT (name_key) DO NOTHING", name)
        cat_ids[name] = await conn.fetchval(
            "SELECT id FROM bs_categories WHERE name_key = lower(regexp_replace(btrim($1), '\\s+', ' ', 'g'))", name)
    listing_rows = []
    for cat, items in LISTING_ITEMS.items():
        for title, desc, lo, hi in items:
            for _ in range(rng.randint(1, 3) if cat in ("Cycles", "Books", "Electronics") else rng.randint(1, 2)):
                created = days_ago(0.2, 150)
                status = rng.choices(["available", "reserved", "sold"], [70, 10, 20])[0]
                if created > NOW - timedelta(days=7):
                    status = "available"
                price = Decimal(round(rng.uniform(lo, hi) / 50) * 50)
                place = rng.choice(HOSTELS + PLACES[:6])
                listing_rows.append((rng.choice(students), title, desc, price, cat_ids[cat], place, status, created))
    await conn.executemany(
        """INSERT INTO listings (seller_id, title, description, price, category_id, location, status, created_at, updated_at)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $8)""", listing_rows)
    counts["listings"] = len(listing_rows)
    listing_ids = [r["id"] for r in await conn.fetch(
        "SELECT id FROM listings WHERE seller_id = ANY($1::uuid[])", users)]

    # Wanted posts and saved searches (rev 6)
    wanted = [("Need a cycle for campus", "Cycles", 3000), ("Looking for a Hero or Btwin cycle", "Cycles", 5000),
              ("Want CLRS (any edition)", "Books", 800), ("Need Bishop PRML", "Books", None),
              ("Looking for a 24-inch monitor", "Electronics", 7000), ("Need a Casio fx-991 calculator", "Electronics", 700),
              ("Raspberry Pi for a course project", "Electronics", 4000), ("Study table needed", "Furniture", 2000),
              ("Office chair for the lab", "Furniture", 3500), ("Induction cooktop", "Kitchen & Appliances", 1500),
              ("Mini fridge for the hostel", "Kitchen & Appliances", 5000), ("Badminton racquet", "Sports & Fitness", 1200),
              ("Formal blazer for interviews", "Clothing", 2000), ("Winter jacket for a trek", "Clothing", None)]
    for title, cat, budget in wanted:
        created = days_ago(0.5, 60)
        await conn.execute(
            """INSERT INTO wanted_posts (author_id, title, description, category_id, max_price, status, created_at, updated_at)
               VALUES ($1, $2, $3, $4, $5, $6, $7, $7)""",
            rng.choice(students), title, rng.choice(["Pick-up anywhere on campus.", "Good condition please.",
                                                     "Can pay by UPI.", None]),
            cat_ids[cat], budget, rng.choices(["open", "fulfilled", "closed"], [75, 15, 10])[0], created)
    counts["wanted posts"] = len(wanted)

    # lost & found
    lf_ids = {}
    for name in LF_ITEMS:
        await conn.execute("INSERT INTO lf_categories (name) VALUES ($1) ON CONFLICT (name_key) DO NOTHING", name)
        lf_ids[name] = await conn.fetchval(
            "SELECT id FROM lf_categories WHERE name_key = lower(regexp_replace(btrim($1), '\\s+', ' ', 'g'))", name)
    n_lost = n_found = 0
    for cat, descs in LF_ITEMS.items():
        for _ in range(rng.randint(1, 3)):
            lost_at = days_ago(1, 90)
            status = rng.choices(["open", "closed"], [75, 25])[0]
            await conn.execute(
                """INSERT INTO lost_reports (reporter_id, description, category_id, lost_at, location, status,
                                             created_at, updated_at) VALUES ($1, $2, $3, $4, $5, $6, $7, $7)""",
                rng.choice(students), rng.choice(descs), lf_ids[cat], lost_at, rng.choice(PLACES),
                status, lost_at + timedelta(hours=rng.uniform(1, 20)))
            n_lost += 1
        for _ in range(rng.randint(1, 2)):
            found_at = days_ago(0.5, 80)
            await conn.execute(
                """INSERT INTO found_reports (reporter_id, description, category_id, found_at, location, status,
                                              created_at, updated_at) VALUES ($1, $2, $3, $4, $5, $6, $7, $7)""",
                rng.choice(students), rng.choice(descs) + ". Collect from me or the security office.", lf_ids[cat],
                found_at, rng.choice(PLACES), rng.choices(["open", "closed"], [70, 30])[0],
                found_at + timedelta(hours=rng.uniform(0.5, 6)))
            n_found += 1
    counts["lost reports"], counts["found reports"] = n_lost, n_found
    # saved searches (rev 6): Buy & Sell ones watch listings, Lost & Found ones watch found reports
    searches = [("buy_sell", "Cycle under ₹3,000", "cycle", "Cycles", None, 3000),
                ("buy_sell", "Cheap textbooks", None, "Books", None, 600),
                ("buy_sell", "Monitor", "monitor", "Electronics", 3000, 9000),
                ("buy_sell", "Anything for the hostel room", None, "Furniture", None, None),
                ("buy_sell", "Mini fridge", "fridge", None, None, 6000),
                ("lost_found", "My ID card", None, "ID card", None, None),
                ("lost_found", "Black wallet", "black", "Wallet", None, None),
                ("lost_found", "Earbuds", None, "Earbuds", None, None)]
    for user in rng.sample(students, 18):
        for module, name, q, cat, low, high in rng.sample(searches, rng.randint(1, 2)):
            await conn.execute(
                """INSERT INTO saved_searches (user_id, module, name, query, bs_category_id, lf_category_id,
                                               min_price, max_price, last_seen_at, created_at, updated_at)
                   VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $10)""",
                user, module, name, q, cat_ids.get(cat) if module == "buy_sell" else None,
                lf_ids.get(cat) if module == "lost_found" else None, low, high, days_ago(3, 20), days_ago(20, 90))
    counts["saved searches"] = await conn.fetchval(
        "SELECT count(*) FROM saved_searches WHERE user_id = ANY($1::uuid[])", users)
    # FR-9 notifications for open lost reports that a later found report matches
    for m in await conn.fetch(
            """SELECT DISTINCT ON (l.id) l.reporter_id, l.id AS lost_id, f.id AS found_id, f.created_at, c.name
               FROM lost_reports l JOIN found_reports f ON f.category_id = l.category_id AND f.found_at >= l.lost_at
               JOIN lf_categories c ON c.id = l.category_id
               WHERE l.reporter_id = ANY($1::uuid[]) AND l.status = 'open' AND f.reporter_id <> l.reporter_id
               ORDER BY l.id, f.created_at""", users):
        notif_rows.append((m["reporter_id"], "lost_found_match", {
            "found_report_id": str(m["found_id"]), "lost_report_ids": [str(m["lost_id"])],
            "message": f"Someone found an item in “{m['name']}”, which matches your lost report."},
            rng.random() < 0.4, m["created_at"]))

    # placement hub: companies, JDs, PPTs, interview experiences, three years of placement sheets
    company_ids = {}
    for name, desc, roles in COMPANIES:
        await conn.execute("INSERT INTO companies (name, description) VALUES ($1, $2) ON CONFLICT (name_key) DO NOTHING",
                           name, desc)
        cid = await conn.fetchval(
            "SELECT id FROM companies WHERE name_key = lower(regexp_replace(btrim($1), '\\s+', ' ', 'g'))", name)
        company_ids[name] = cid
        for role in roles:
            await conn.execute("INSERT INTO job_descriptions (company_id, role_title) VALUES ($1, $2)", cid, role)
        if rng.random() < 0.6:
            await conn.execute("INSERT INTO ppt_info (company_id, details, scheduled_at) VALUES ($1, $2, $3)", cid,
                               f"Pre-placement talk by {name}: roles, process and Q&A. Venue: Faculty Hall.",
                               NOW + timedelta(days=rng.randint(3, 40), hours=rng.randint(0, 8)))
    n_exp = 0
    for name, _, roles in COMPANIES:
        for _ in range(rng.randint(1, 4)):
            role = rng.choice(roles)
            q1, q2 = rng.sample(DSA, 2)
            t1, t2 = rng.sample(TECH, 2)
            difficulty = rng.choice(["Easy", "Medium", "Medium", "Hard"])
            content = (f"Role: {role}.\n"
                       f"Round 1 (online assessment, 90 min): two coding questions, {q1} and {q2}.\n"
                       f"Round 2 (technical): {t1}; then a deep dive into my M.Tech project.\n"
                       f"Round 3 (technical/managerial): {t2} and a discussion of trade-offs.\n"
                       f"Round 4 (HR): why {name}, relocation, and timelines.\n"
                       f"Difficulty: {difficulty}. Tip: {rng.choice(ADVICE).format(topic=t1)}")
            await conn.execute(
                """INSERT INTO interview_experiences (company_id, author_id, role_title, content, created_at, updated_at)
                   VALUES ($1, $2, $3, $4, $5, $5)""", company_ids[name], rng.choice(users), role, content,
                days_ago(20, 700))
            n_exp += 1
    counts["interview experiences"] = n_exp
    n_records = 0
    for year in (2024, 2025, 2026):
        rows, seen = [], set()
        for name, _, roles in COMPANIES:
            for _ in range(rng.randint(1, 9)):
                while True:
                    email = f"{rng.choice(FIRST).lower()}{rng.choice(LAST).lower()}{rng.randint(1, 99)}@iisc.ac.in"
                    if email not in seen:
                        seen.add(email)
                        break
                rows.append((year, f"Slot {rng.randint(1, 3)}", company_ids[name], rng.choice(roles), email))
        import_id = await conn.fetchval(
            """INSERT INTO placement_bulk_imports (moderator_id, placement_year, source_s3_key, rows_total, rows_created,
                                                   rows_updated, rows_rejected, imported_at)
               VALUES ($1, $2, $3, $4, $4, 0, 0, $5) RETURNING id""",
            mods["placement_hub"], year, f"placement-imports/seed-{year}.csv", len(rows), at(year, 7, 15))
        await conn.executemany(
            """INSERT INTO placement_records (import_id, placement_year, slot, company_id, role_title, student_email)
               VALUES ($6, $1, $2, $3, $4, $5)""", [r + (import_id,) for r in rows])
        n_records += len(rows)
    counts["placement records"] = n_records

    # events, tag follows, bookmarks
    tag_ids = {}
    for tag in EVENT_TAGS:
        await conn.execute("INSERT INTO event_tags (name) VALUES ($1) ON CONFLICT (name) DO NOTHING", tag)
        tag_ids[tag] = await conn.fetchval("SELECT id FROM event_tags WHERE name = $1", tag)
    event_ids = []
    for i, (title, tag, place, desc) in enumerate(EVENTS):
        if i < 5:
            start = NOW - timedelta(days=rng.uniform(3, 60))        # past
        elif i == 5:
            start = NOW - timedelta(hours=1)                        # happening now
        else:
            start = NOW + timedelta(days=rng.uniform(1, 75))        # upcoming
        start = start.replace(minute=0, second=0, microsecond=0)
        eid = await conn.fetchval(
            """INSERT INTO events (created_by, title, description, location, start_time, end_time, created_at, updated_at)
               VALUES ($1, $2, $3, $4, $5, $6, $7, $7) RETURNING id""",
            rng.choice(students), title, desc, place, start, start + timedelta(hours=rng.choice([1, 2, 3, 4])),
            start - timedelta(days=rng.uniform(5, 20)))
        await conn.execute("INSERT INTO event_tag_map (event_id, tag_id) VALUES ($1, $2)", eid, tag_ids[tag])
        event_ids.append(eid)
    counts["events"] = len(event_ids)
    for user in rng.sample(students, 25):
        for tag in rng.sample(EVENT_TAGS, rng.randint(1, 3)):
            await conn.execute("INSERT INTO tag_follows (user_id, tag_id) VALUES ($1, $2)", user, tag_ids[tag])
        for target_type, pool in (("listing", listing_ids), ("event", event_ids)):
            for target in rng.sample(pool, rng.randint(0, 3)):
                await conn.execute("INSERT INTO bookmarks (user_id, target_type, target_id) VALUES ($1, $2, $3) "
                                   "ON CONFLICT DO NOTHING", user, target_type, target)

    # reports for the moderation queue (open), plus a few already handled
    report_specs = [
        ("listing", "buy_sell", "listing_id", "SELECT id FROM listings WHERE seller_id = ANY($1::uuid[])",
         ["Price looks like a scam, seller asked for advance payment.", "Same photo used in another listing.",
          "Item is prohibited in hostels."]),
        ("found_report", "lost_found", "found_report_id", "SELECT id FROM found_reports WHERE reporter_id = ANY($1::uuid[])",
         ["Description contains someone's phone number."]),
        ("course_feedback", "academic_help", "course_feedback_id",
         "SELECT id FROM course_feedback WHERE author_id = ANY($1::uuid[])",
         ["Personal attack on the instructor.", "Off-topic rant, not feedback."]),
        ("interview_experience", "placement_hub", "interview_experience_id",
         "SELECT id FROM interview_experiences WHERE author_id = ANY($1::uuid[])",
         ["Shares questions under NDA."]),
    ]
    n_reports = 0
    for target_type, module, column, query, reasons in report_specs:
        targets = [r["id"] for r in await conn.fetch(query, users)]
        for target in rng.sample(targets, min(3, len(targets))):
            handled = rng.random() < 0.35
            handler = admin if handled else None
            await conn.execute(
                f"""INSERT INTO reports (reporter_id, module, target_type, {column}, reason, status, handled_by,
                                         handled_at, resolution_note, created_at, updated_at)
                    VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $10)""",
                rng.choice(students), module, target_type, target, rng.choice(reasons),
                "dismissed" if handled else "open", handler, NOW - timedelta(days=1) if handled else None,
                "Looked fine on review." if handled else None, days_ago(1, 20))
            n_reports += 1
    counts["reports"] = n_reports

    # notifications collected above, and a few buyer-seller chats
    await conn.executemany(
        "INSERT INTO notifications (user_id, type, payload, is_read, created_at) VALUES ($1, $2, $3, $4, $5)",
        notif_rows)
    counts["notifications"] = len(notif_rows)
    chats = [("Hi, is the {item} still available?", "Yes, it is. You can come see it this evening."),
             ("Would you take a bit less for the {item}?", "I can do a small discount if you pick it up today."),
             ("Can I see the {item} near the library tomorrow?", "Sure, 5 pm at the library entrance works.")]
    n_chat = 0
    for row in (await conn.fetch("SELECT id, seller_id, title, created_at FROM listings "
                                 "WHERE seller_id = ANY($1::uuid[]) AND status <> 'sold' ORDER BY random() LIMIT 12",
                                 users)):
        buyer = rng.choice([u for u in students if u != row["seller_id"]])
        ask, answer = rng.choice(chats)
        t = max(row["created_at"], NOW - timedelta(days=10)) + timedelta(hours=rng.uniform(1, 30))
        if t > NOW:
            t = NOW - timedelta(minutes=rng.randint(5, 300))
        await conn.execute("INSERT INTO chat_messages (sender_id, receiver_id, content, sent_at, read_at) "
                           "VALUES ($1, $2, $3, $4, $4)", buyer, row["seller_id"],
                           ask.format(item=row["title"]), t)
        await conn.execute("INSERT INTO chat_messages (sender_id, receiver_id, content, sent_at) "
                           "VALUES ($1, $2, $3, $4)", row["seller_id"], buyer, answer,
                           min(t + timedelta(minutes=rng.randint(5, 120)), NOW))
        n_chat += 2
    counts["chat messages"] = n_chat
    return counts


async def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--reset", action="store_true", help="remove the dummy data, then add it again")
    group.add_argument("--remove", action="store_true", help="only remove the dummy data")
    args = parser.parse_args()

    s3 = s3_client()
    bucket = ENV.get("CAMPUSHUB_S3_BUCKET", "campushub-uploads")
    conn = await asyncpg.connect(DB_URL)
    try:
        await conn.set_type_codec("jsonb", encoder=json.dumps, decoder=json.loads,
                                  schema="pg_catalog")
        present = await conn.fetchval("SELECT count(*) FROM users WHERE email::text = ANY($1::text[])", SEED_EMAILS)
        if present and not (args.reset or args.remove):
            sys.exit("The dummy data is already there. Use --reset to recreate it or --remove to delete it.")
        async with conn.transaction():
            old_keys = await remove_seed(conn)
            counts = {} if args.remove else await seed(conn, s3, bucket)
        for i in range(0, len(old_keys), 1000):
            s3.delete_objects(Bucket=bucket, Delete={"Objects": [{"Key": k} for k in old_keys[i:i + 1000]]})
    finally:
        await conn.close()
    if args.remove:
        print(f"Removed the dummy data ({len(old_keys)} material files deleted from storage).")
        return
    print("Added dummy data:")
    for name, n in counts.items():
        print(f"  {name:<22} {n}")
    print(f"\nSign in as any of them with  X-Dev-User: {SEED_EMAILS[0]}  (all {len(SEED_EMAILS)} are in SEED_USERS).")


if __name__ == "__main__":
    asyncio.run(main())
