# check=skip=SecretsUsedInArgOrEnv
# Dockerfile for SSH test server
FROM ubuntu:24.04

# Install SSH server
RUN apt-get update
RUN apt-get install -y openssh-server
RUN mkdir -p /var/run/sshd

# Create test user and set password
ENV USERNAME=myuser
ENV PASSWORD=mypass

RUN useradd -m -s /bin/bash $USERNAME
RUN echo "$USERNAME:$PASSWORD" | chpasswd

# Allow password authentication
RUN sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication yes/' /etc/ssh/sshd_config
RUN sed -i 's/^#\?PermitRootLogin .*/PermitRootLogin yes/' /etc/ssh/sshd_config
RUN sed -i 's/^#\?PubkeyAuthentication .*/PubkeyAuthentication yes/' /etc/ssh/sshd_config

# Set up SSH keys for public key authentication
RUN mkdir -p /home/$USERNAME/.ssh
RUN chmod 700 /home/$USERNAME/.ssh
RUN chown $USERNAME:$USERNAME /home/$USERNAME/.ssh

# Copy test SSH key (will be generated separately)
COPY Data/authorized_keys /home/$USERNAME/.ssh/authorized_keys
RUN chmod 600 /home/$USERNAME/.ssh/authorized_keys
RUN chown $USERNAME:$USERNAME /home/$USERNAME/.ssh/authorized_keys

# Copy test data
COPY Data/lorem-ipsum.txt /home/$USERNAME/lorem-ipsum.txt

# Expose SSH port
EXPOSE 22

# Start SSH service
CMD ["/usr/sbin/sshd", "-D"]
