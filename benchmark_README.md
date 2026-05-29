run_benchmark_sorted.sh
<img width="953" height="440" alt="image" src="https://github.com/user-attachments/assets/f2755824-b0e4-48dd-9887-48e33b0a3781" />

Порог слома - 4-5 сессий, QPS перестает расти, растет p99 на 40%, QPS 27-28 сессий. 


run_benchmark_nosorted.sh
<img width="935" height="439" alt="image" src="https://github.com/user-attachments/assets/07856ab4-2014-4244-ae2b-ecb64a594e45" />
Порог слома 1-2 сессий, p99 растет линейно 25%, 50%, 75%. QPS низкий, всего 4 сессии. 
