# bash_utils.py
import subprocess

def call_bash_function(script_path, function_name, *args):
    # Join the arguments into a single string
    args_str = " ".join(args)
    
    bash_command = f"source {script_path} && {function_name} {args_str}"
    subprocess.run(["bash", "-c", bash_command], check=True)

