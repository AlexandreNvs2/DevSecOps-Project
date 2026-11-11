from flask import Flask, request, render_template 
 
app = Flask(__name__) 
 
def worst_500_passwords(password): 
 
  #Download the SecList 
  import requests 
  print('Beginning check in 500 worst passwords') 
  url = 'https://raw.githubusercontent.com/danielmiessler/SecLists/master/Passwords/Common-Credentials/500-worst-passwords.txt' 
  retrieve = requests.get(url) 
  content = retrieve.content 
  if str(password) in str(content): 
    return 1 
 
def worst_10k_passwords(password): 
 
  #Download the SecList 
  import requests 
  print('Beginning check in 10K worst passwords') 
  url = 'https://raw.githubusercontent.com/danielmiessler/SecLists/master/Passwords/Common-Credentials/10k-most-common.txt' 
  retrieve = requests.get(url) 
  content = retrieve.content 
  if str(password) in str(content): 
    return 1 
 
@app.route('/') 
def hello(): 
    return 'Welcome to the website. Go to /password to check your password !' 
 
@app.route('/password', methods = ["GET", "POST"]) 
def password(): 
    if request.method == "POST": 
        password = request.form.get("password") 
        if worst_500_passwords(password) == 1 : 
            return "Your password is in 500 worst passwords... Change it immediately" 
        elif worst_10k_passwords(password) == 1 : 
            return "Your password is in 10K worst passwords... Change it immediately" 
        else: 
            return "Your password seems to be safe" 
    return render_template("password.html") 
 
if __name__ == '__main__': 
    app.run(port=8080, host='0.0.0.0') 