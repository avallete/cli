package seed

type Config struct {
	Path       string
	IsProvided bool
}

func NewConfig(path string, isProvided bool) Config {
	return Config{
		Path:       path,
		IsProvided: isProvided,
	}
}
