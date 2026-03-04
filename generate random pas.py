# write a program to generate random passwords   
import random
import string

# Function to generate a random password
def generate_password(length=12):
    # Define possible characters: letters, digits, and punctuation
    characters = string.ascii_letters + string.digits + string.punctuation
    
    # Randomly choose characters
    password = ''.join(random.choice(characters) for _ in range(length))
    return password

# Example usage
print("Generated password:", generate_password(12))