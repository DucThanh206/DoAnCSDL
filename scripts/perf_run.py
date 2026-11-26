import pymysql, time, statistics, random, json
c = pymysql.connect(unix_socket='/var/run/mysqld/mysqld.sock', user='root', database='mini_upwork_perf', autocommit=True)
cur = c.cursor()
cur.execute('SELECT job_id FROM jobs'); JOBS=[x[0] for x in cur.fetchall()]
cur.execute('SELECT contract_id FROM contracts'); CON=[x[0] for x in cur.fetchall()]
cur.execute('SELECT user_id FROM users WHERE user_id>5'); USR=[x[0] for x in cur.fetchall()]
cases = [
 ("P-01","jobs(status,created_at)","SELECT job_id,title,created_at FROM jobs {h} WHERE status='OPEN' ORDER BY created_at DESC LIMIT 20", lambda: ()),
 ("P-02","proposals(job_id,status)","SELECT proposal_id,freelancer_id,bid_amount FROM proposals {h} WHERE job_id=%s AND status='PENDING'", lambda: (random.choice(JOBS),)),
 ("P-03","milestones(contract_id,status)","SELECT milestone_id,sequence_no,status FROM milestones {h} WHERE contract_id=%s AND status='PENDING'", lambda: (random.choice(CON),)),
 ("P-04","transactions(payee_id,created_at)","SELECT transaction_id,gross_amount,created_at FROM transactions {h} WHERE payee_id=%s ORDER BY created_at DESC LIMIT 20", lambda: (random.choice(USR),)),
 ("P-05","reviews(reviewee_id)","SELECT review_id,reviewer_id,rating FROM reviews {h} WHERE reviewee_id=%s", lambda: (random.choice(USR),)),
]
def run(sql, pf, n=20):
    ts=[]
    for _ in range(n):
        t=time.perf_counter(); cur.execute(sql, pf()); cur.fetchall(); ts.append((time.perf_counter()-t)*1000)
    ts.sort(); return statistics.median(ts), ts[int(0.95*n)-1]
out=[]
for cid,idx,q,pf in cases:
    ex = q.format(h='').replace('%s','1')
    cur.execute("EXPLAIN "+ex); r=cur.fetchone()  # id,select_type,table,partitions,type,possible_keys,key,key_len,ref,rows
    key, rows = r[6], r[9]
    cur.execute("EXPLAIN "+q.format(h='FORCE INDEX (PRIMARY)').replace('%s','1')); r2=cur.fetchone()
    p50i,p95i = run(q.format(h=''), pf)
    p50f,p95f = run(q.format(h='FORCE INDEX (PRIMARY)'), pf)
    out.append((cid,idx,key,rows,round(p50i,2),round(p95i,2),r2[9],round(p50f,2),round(p95f,2)))
    print(cid, idx, "| key:",key,"rows:",rows,"| idx p50/p95 ms:",round(p50i,2),round(p95i,2),"| full-scan rows:",r2[9],"p50/p95 ms:",round(p50f,2),round(p95f,2))
json.dump(out,open('perf.json','w'))
