# write a program that allow users three attepmt and two enter correct password during exception handling
# Program: Password check with 3 attempts

# Set the correct password
correct_password = "Python123"

attempts = 3

for i in range(attempts):
    try:
        user_input = input("Enter your password: ")

        if user_input == correct_password:
            print("Access Granted ✅")
            break
        else:
            raise ValueError("Incorrect password")

    except ValueError as e:
        print(e)
        print(f"Attempts left: {attempts - i - 1}")

else:
    print("❌ Access Denied. Too many failed attempts.")