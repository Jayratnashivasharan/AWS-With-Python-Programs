# write a function that chack the age if age is >80 raise exception such as "NOT Eligible"
# Custom exception class
class AgeNotEligibleError(Exception):
    pass

# Function to check age
def check_age(age):
    if age < 0:
        return "Invalid age. Age cannot be negative."
    elif age > 80:
        raise AgeNotEligibleError("NOT Eligible")
    elif age < 18:
        return "You are a minor."
    elif age < 60:
        return "You are an adult."
    else:
        return "You are a senior citizen."

# Example usage
try:
    user_age = int(input("Enter your age: "))
    print(check_age(user_age))
except AgeNotEligibleError as e:
    print("Exception:", e)