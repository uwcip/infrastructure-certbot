# infrastructure-certbot
This container lets you manage a [certbot](https://pypi.org/project/certbot/)
system. When the container starts it just goes into a loop that checks to every
four hours to see if any certificates need to be renewed. You can exec into it
to run renewals manually or to create new certificates.

## Using This Container

This container needs two permanent volumes: a data directory for storing the
certificates and a log directory for storing the logs from certbot mounted to
`/etc/letsencrypt` and `/var/log/letsencrypt`, respectively. (The log file is
probably optional, actually, if you're capturing the stdout somewhere, but
certbot will write and rotate log files in your container.)

By default, when this container starts, it will immediately go into a "renew"
loop, trying to renew any certificates that it finds in the data directory.

If you're running the `renew` loop on a Kubernetes cluster somewhere and you
have a volume with your certificates on it, you can use the certbot client by
`exec`ing into the container and telling it to create new certificates, like
this:

    POD=$(kubectl get pods -n support -l service=certbot -o jsonpath="{.items[0].metadata.name}")
    kubectl exec -it -c certbot -n support $POD -- certbot ...

Obviously, replace the `...` with the command that you wish to send to the
certbot program. And maybe not so obviously be sure to set the correct
namespace where the certbot pod is running.

Finally, if you have hooks that you want to call then you can place them in the
`/etc/letsencrypt/renewal-hooks` under either `post, `pre`, or `deploy`. You
can do this either in the mounted data directory or with another volume that
gets mounted specifically into those directories like a ConfigMap or something.

## Using with `acme-dns`

This container is intended to run in a pod alongside another container running
[acme-dns](https://github.com/joohoi/acme-dns). Before you can use `acme-dns`
you will need to configure it. Assuming that it is running on localhost on port
5380 you can run this command:

    curl -X POST -H 'Content-Type: application/json' -d '{"allowfrom": ["127.0.0.1/32"]}' http://127.0.0.1:5380/register

Additionally, you will need to create a file that contains registration
information for each domain that you will manage with certbot. It should look
a bit like this:

    {
        "example.com": {
            "username":"some-uuid",
            "password":"super secret password",
            "subdomain":"the domain to look at for the token"
        },
        "example.org": {
            "username":"some-uuid",
            "password":"super secret password",
            "subdomain":"the domain to look at for the token"
        }
    }

Each of the fields **may** be exactly the same but you must list each domain
separately. Then ensure that you have a CNAME set up for your domain that looks
like this:

    _acme-challenge.example.com IN CNAME some-uuid.myacmednshost.example.com

Finally, ensure that you have these records set up:

    myacmednshost.example.com IN A 1.2.3.4
    myacmednshost.example.com IN NS myacmednshost.example.com

This way DNS requests for *.myacmednshost.example.com will be sent to your
instance of acme-dns where certbot can provide the correct answers.

## Creating a Certificate

Note that scripts in the `renewal-hooks` directory will _not_ be run on a call
to `certonly`. They only get run on calls to `renew`. That is to say that you
should manually run any hooks that you want to run after calling `certonly` to
create a new certificate.

Therefore, to set up a new domain you can call it like this:

    POD=$(kubectl get pods -n support -l service=certbot -o jsonpath="{.items[0].metadata.name}")
    kubectl exec -it -c certbot -n support $POD -- certbot certonly --emailnoreply@example.com \
        --no-eff-email --manual --manual-auth-hook /usr/local/bin/acme-dns --preferred-challenge dns \
        -d "example.com,*.example.com"

After running the `certonly` command be sure to any any post hooks that you
have that are necessary for distributing the new certificates to, for example,
your load balancers.

## Internal Notes

Internal to CIP, this is how we create certificates:

    POD=$(kubectl get pods -n support -l service=certbot -o jsonpath="{.items[0].metadata.name}")
    kubectl exec -it -c certbot -n support $POD -- certbot certonly --email ciptools@uw.edu \
        --no-eff-email --manual --manual-auth-hook /usr/local/bin/acme-dns --preferred-challenge dns \
        -d "example.edu,*.example.edu"
    kubectl exec -it -c certbot -n support $POD -- /etc/letsencrypt/renewal-hooks/post/update-load-balancers

