package main

import (
	"errors"
	"os"
	"strconv"

	pb "github.com/eagletmt/kaede/kaede-cli/kaede/grpc"
	"github.com/golang/protobuf/jsonpb"
	"github.com/urfave/cli"
	"golang.org/x/net/context"
	"google.golang.org/grpc"
)

func main() {
	app := cli.NewApp()

	app.Usage = "CLI for kaede"
	app.Commands = []cli.Command{
		{
			Name:  "reload",
			Usage: "Reload scheduler",
			Flags: []cli.Flag{
				cli.StringFlag{
					Name:  "address, a",
					Value: "localhost:4195",
				},
			},
			Action: func(c *cli.Context) error {
				return withClient(c, reload)
			},
		},
		{
			Name:  "stop",
			Usage: "Stop scheduler",
			Flags: []cli.Flag{
				cli.StringFlag{
					Name:  "address, a",
					Value: "localhost:4195",
				},
			},
			Action: func(c *cli.Context) error {
				return withClient(c, stop)
			},
		},
		{
			Name:  "list-programs",
			Usage: "List programs",
			Flags: []cli.Flag{
				cli.StringFlag{
					Name:  "address, a",
					Value: "localhost:4195",
				},
			},
			Action: func(c *cli.Context) error {
				return withClient(c, listPrograms)
			},
		},
		{
			Name:  "add-tid",
			Usage: "Add tid",
			Flags: []cli.Flag{
				cli.StringFlag{
					Name:  "address, a",
					Value: "localhost:4195",
				},
			},
			Action: func(c *cli.Context) error {
				return withClient(c, addTid)
			},
		},
		{
			Name:  "update",
			Usage: "Update",
			Flags: []cli.Flag{
				cli.StringFlag{
					Name:  "address, a",
					Value: "localhost:4195",
				},
			},
			Action: func(c *cli.Context) error {
				return withClient(c, update)
			},
		},
		{
			Name:  "add-channel",
			Usage: "Add channel",
			Flags: []cli.Flag{
				cli.StringFlag{
					Name:  "address, a",
					Value: "localhost:4195",
				},
				cli.UintFlag{
					Name: "recorder",
				},
				cli.UintFlag{
					Name: "syoboi",
				},
			},
			Action: func(c *cli.Context) error {
				return withClient(c, addChannel)
			},
		},
	}
	app.Action = func(*cli.Context) error {
		return errors.New("No subcommand given")
	}
	app.Run(os.Args)

}

func withClient(c *cli.Context, f func(*cli.Context, pb.SchedulerClient) error) error {
	addr := c.String("address")
	conn, err := grpc.Dial(addr, grpc.WithInsecure())
	if err != nil {
		return err
	}
	defer conn.Close()
	return f(c, pb.NewSchedulerClient(conn))

}

func reload(_ *cli.Context, client pb.SchedulerClient) error {
	_, err := client.Reload(context.Background(), &pb.SchedulerReloadInput{})
	return err
}

func stop(_ *cli.Context, client pb.SchedulerClient) error {
	_, err := client.Stop(context.Background(), &pb.SchedulerStopInput{})
	return err
}

func listPrograms(_ *cli.Context, client pb.SchedulerClient) error {
	result, err := client.GetPrograms(context.Background(), &pb.GetProgramsInput{})
	if err != nil {
		return err
	}
	for _, program := range result.Programs {
		m := &jsonpb.Marshaler{}
		m.Marshal(os.Stdout, program)
		os.Stdout.Write([]byte{'\n'})
	}
	return nil
}

func addTid(c *cli.Context, client pb.SchedulerClient) error {
	tidString := c.Args().First()
	if tidString == "" {
		return errors.New("add-tid requires 1 argument")
	}
	tid, err := strconv.Atoi(tidString)
	if err != nil {
		return err
	}
	_, err = client.AddTid(context.Background(), &pb.AddTidInput{Tid: uint32(tid)})
	return err
}

func update(_ *cli.Context, client pb.SchedulerClient) error {
	_, err := client.Update(context.Background(), &pb.UpdateInput{})
	return err
}

func addChannel(c *cli.Context, client pb.SchedulerClient) error {
	recorder := c.Uint("recorder")
	if recorder == 0 {
		return errors.New("--recorder is required")
	}
	syoboi := c.Uint("syoboi")
	if syoboi == 0 {
		return errors.New("--syoboi is required")
	}
	name := c.Args().First()
	if name == "" {
		return errors.New("name is required")
	}

	_, err := client.AddChannel(context.Background(), &pb.AddChannelInput{Name: name, Recorder: uint32(recorder), Syoboi: uint32(syoboi)})
	return err
}
