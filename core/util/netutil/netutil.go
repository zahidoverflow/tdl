package netutil

import (
	"net/url"
	"os"
	"strconv"

	"github.com/go-faster/errors"
	"github.com/iyear/connectproxy"
	"golang.org/x/net/proxy"
)

func init() {
	insecureSkipVerify := false
	if v := os.Getenv("TDL_INSECURE_SKIP_VERIFY"); v != "" {
		if b, err := strconv.ParseBool(v); err == nil {
			insecureSkipVerify = b
		}
	}

	connectproxy.Register(&connectproxy.Config{
		InsecureSkipVerify: insecureSkipVerify,
	})
}

func NewProxy(proxyUrl string) (proxy.ContextDialer, error) {
	u, err := url.Parse(proxyUrl)
	if err != nil {
		return nil, errors.Wrap(err, "parse proxy url")
	}
	dialer, err := proxy.FromURL(u, proxy.Direct)
	if err != nil {
		return nil, errors.Wrap(err, "proxy from url")
	}

	if d, ok := dialer.(proxy.ContextDialer); ok {
		return d, nil
	}

	return nil, errors.New("proxy dialer is not ContextDialer")
}
