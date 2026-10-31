"""Formula check using SQLite (same GROUP BY / FILTER logic as the Postgres functions)."""
import sqlite3
db = sqlite3.connect(":memory:")
db.executescript("""
create table ses(id integer primary key, class_id, subject, d, period, unique(class_id, subject, d, period));
create table rec(session_id, student, status, primary key(session_id, student));
""")
# Physics: 10 classes, student attended 10. Maths: 2 classes, attended 0. Chemistry: 8 classes, attended 6.
sid = 0
def add(subject, n, present):
    global sid
    for i in range(n):
        sid += 1
        db.execute("insert into ses values(?,?,?,?,?)", (sid, "C1", subject, f"2026-10-{i+1:02d}", 1))
        db.execute("insert into rec values(?,?,?)", (sid, "S1", "P" if i < present else "A"))
add("Physics", 10, 10); add("Maths", 2, 0); add("Chemistry", 8, 6)

total, present = db.execute("select count(*), sum(status='P') from rec where student='S1'").fetchone()
overall = round(100.0 * present / total, 2)
per_subject = db.execute("""select s.subject, round(100.0*sum(r.status='P')/count(*),2) from rec r join ses s on s.id=r.session_id
                            where r.student='S1' group by s.subject""").fetchall()
avg_of_avgs = round(sum(p for _, p in per_subject) / len(per_subject), 2)
print("subjects:", per_subject)
print("overall (present/conducted):", overall, "| average of subject %:", avg_of_avgs)
assert (total, present) == (20, 16) and overall == 80.0
assert avg_of_avgs != overall, "spec requires present/conducted, not average of averages"
print("PASS overall = 16/20 = 80.00 (an average of subject % would wrongly give", avg_of_avgs, ")")

try:
    db.execute("insert into ses values(99,'C1','Physics','2026-10-01',1)")
    raise SystemExit("FAIL duplicate session was accepted")
except sqlite3.IntegrityError:
    print("PASS duplicate class+subject+date+period is rejected")
db.execute("insert into ses values(100,'C1','Physics','2026-10-01',2)")
print("PASS a different period on the same day is allowed")
