from pathlib import Path

from flask import Flask, request, render_template

app = Flask(__name__)

DATA_DIR = Path(__file__).parent / "data"


def load_wordlist(filename):
    """Charge une liste de mots de passe une seule fois, au démarrage."""
    path = DATA_DIR / filename
    with path.open(encoding="utf-8", errors="ignore") as f:
        return frozenset(line.strip() for line in f if line.strip())


WORST_500 = load_wordlist("500-worst-passwords.txt")
WORST_10K = load_wordlist("10k-most-common.txt")

MAX_PASSWORD_LENGTH = 128
 
@app.route('/') 
def hello(): 
    return 'Welcome to the website. Go to /password to check your password !' 
 
@app.route('/password', methods = ["GET", "POST"]) 
def password(): 
    if request.method == "POST": 
        password = request.form.get("password", "")
        if not password or len(password) > MAX_PASSWORD_LENGTH:
            return "Invalid password", 400
        if password in WORST_500:
            return "Your password is in 500 worst passwords... Change it immediately" 
        elif password in WORST_10K:
            return "Your password is in 10K worst passwords... Change it immediately" 
        else: 
            return "Your password seems to be safe" 
    return render_template("password.html") 
 
if __name__ == '__main__': 
    app.run(port=8080, host='0.0.0.0') 