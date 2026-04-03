# Use an Nginx image to serve the content
FROM nginx:alpine

# Copy the build artifacts from the build/web directory to the default Nginx public directory
COPY build/web /usr/share/nginx/html

# Expose port 80
EXPOSE 80

# The default command runs Nginx in the foreground
CMD ["nginx", "-g", "daemon off;"]
